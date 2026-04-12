assistant_base_url <- function() {
  "https://ellm.nrp-nautilus.io/v1/"
}

assistant_models_url <- function() {
  paste0(sub("/+$", "", assistant_base_url()), "/models")
}

assistant_default_model <- function() {
  model_name <- Sys.getenv("NRP_MODEL", unset = "")
  if (nzchar(model_name)) {
    model_name
  } else {
    "qwen3-small"
  }
}

assistant_is_available <- function() {
  requireNamespace("ellmer", quietly = TRUE) && nzchar(Sys.getenv("NRP_API_KEY"))
}

assistant_open_webui_url <- function() {
  url <- Sys.getenv("NRP_OPEN_WEBUI_URL", unset = "")
  if (nzchar(url)) url else NA_character_
}

assistant_dashboard_url <- function() {
  url <- Sys.getenv("CARBON_DASHBOARD_URL", unset = "")
  if (!nzchar(url)) {
    url <- Sys.getenv("NRP_DASHBOARD_URL", unset = "")
  }
  if (nzchar(url)) {
    url
  } else {
    "https://carbon-api.nrp-nautilus.io/"
  }
}

assistant_external_links <- function() {
  list(
    list(
      label = "Carbon Dashboard",
      href = assistant_dashboard_url(),
      external = TRUE,
      icon = "leaf"
    )
  )
}

assistant_filter_chat_models <- function(model_tbl) {
  if (is.null(model_tbl) || nrow(model_tbl) == 0) {
    return(model_tbl)
  }

  keep <- model_tbl$object == "model" &
    !grepl("embedding", model_tbl$id, ignore.case = TRUE) &
    !grepl("test", model_tbl$id, ignore.case = TRUE)

  model_tbl[keep, , drop = FALSE]
}

assistant_fetch_model_catalog <- function() {
  fallback_model <- assistant_default_model()
  fallback_tbl <- tibble::tibble(
    id = fallback_model,
    label = fallback_model,
    owned_by = "fallback"
  )

  if (!assistant_is_available()) {
    return(list(models = fallback_tbl, fallback_used = TRUE, error = "Assistant API key is unavailable."))
  }

  result <- tryCatch({
    req <- httr2::request(assistant_models_url()) |>
      httr2::req_headers(Authorization = paste("Bearer", Sys.getenv("NRP_API_KEY")))
    payload <- httr2::resp_body_json(httr2::req_perform(req), simplifyVector = TRUE)
    model_tbl <- payload$data
    if (is.null(model_tbl) || NROW(model_tbl) == 0) {
      stop("Model list response was empty.")
    }
    model_tbl <- tibble::as_tibble(model_tbl)
    model_tbl <- assistant_filter_chat_models(model_tbl)
    if (nrow(model_tbl) == 0) {
      stop("No chat-suitable models were returned by the endpoint.")
    }

    model_tbl <- model_tbl |>
      dplyr::transmute(
        id = as.character(id),
        label = if (!is.null(owned_by)) paste0(id, " (", owned_by, ")") else as.character(id),
        owned_by = if (!is.null(owned_by)) as.character(owned_by) else NA_character_
      )

    if (!(fallback_model %in% model_tbl$id)) {
      model_tbl <- dplyr::bind_rows(
        tibble::tibble(id = fallback_model, label = paste0(fallback_model, " (default)"), owned_by = "default"),
        model_tbl
      ) |>
        dplyr::distinct(id, .keep_all = TRUE)
    }

    list(models = model_tbl, fallback_used = FALSE, error = NULL)
  }, error = function(e) {
    list(models = fallback_tbl, fallback_used = TRUE, error = conditionMessage(e))
  })

  result
}

assistant_system_prompt <- function() {
  paste(
    "You are the Urban Tree Explorer Data Assistant inside a Shiny app.",
    "Be concise, factual, and action-oriented.",
    "Use registered tools for factual claims about totals, city metrics, species, viewport contents, and map actions.",
    "Do not claim to inspect files, run code, browse the web, or access data outside the provided tools and context.",
    "If a map action is requested, prefer the explicit action tools.",
    "If the user asks for a comparison, call the needed tools for each city and summarize clearly.",
    sep = "\n"
  )
}

assistant_view_mode <- function(state) {
  rules <- map_zoom_rules()

  if (nzchar(state$selected_city %||% "")) {
    "city-selected"
  } else if ((state$zoom %||% 0) >= rules$point_min) {
    "high-zoom viewport"
  } else if ((state$zoom %||% 0) >= rules$aggregate_min) {
    "city-scale viewport"
  } else {
    "national"
  }
}

assistant_state_snapshot <- function(state) {
  city_row <- get_city_summary_row(state$selected_city %||% "")
  city_label <- if (is.null(city_row)) "none" else paste0(city_row$city[[1]], ", ", city_row$state[[1]])
  active_row <- get_city_summary_row(state$active_city %||% "")
  active_label <- if (is.null(active_row)) "none" else paste0(active_row$city[[1]], ", ", active_row$state[[1]])
  intersecting_labels <- vapply(state$intersecting_cities %||% character(), function(city_key) {
    row <- get_city_summary_row(city_key)
    if (is.null(row)) city_key else paste0(row$city[[1]], ", ", row$state[[1]])
  }, character(1))

  bbox_line <- if (is.null(state$bbox)) {
    "none"
  } else {
    paste0(
      "xmin=", round(state$bbox$xmin, 4),
      ", ymin=", round(state$bbox$ymin, 4),
      ", xmax=", round(state$bbox$xmax, 4),
      ", ymax=", round(state$bbox$ymax, 4)
    )
  }

  paste(
    "Current app context:",
    paste0("- View mode: ", assistant_view_mode(state)),
    paste0("- Selected city: ", city_label),
    paste0("- Selected species: ", state$selected_species %||% "none"),
    paste0("- Active viewport city: ", active_label),
    paste0("- Intersecting viewport cities: ", if (length(intersecting_labels) == 0) "none" else paste(intersecting_labels, collapse = "; ")),
    paste0("- Zoom: ", round(state$zoom %||% national_view()$zoom, 2)),
    paste0("- Bounding box: ", bbox_line),
    sep = "\n"
  )
}

assistant_prompt <- function(user_message, state) {
  paste(
    assistant_state_snapshot(state),
    "",
    "User request:",
    user_message,
    sep = "\n"
  )
}

create_session_assistant_chat <- function(session, state_getter, pending_species_setter = function(value) NULL, model = assistant_default_model()) {
  if (!assistant_is_available()) {
    return(NULL)
  }

  tryCatch({
    chat <- ellmer::chat_openai_compatible(
      base_url = assistant_base_url(),
      name = "NRP",
      system_prompt = assistant_system_prompt(),
      credentials = function() Sys.getenv("NRP_API_KEY"),
      model = model,
      echo = "none"
    )

    chat$register_tools(build_assistant_tools(
      session = session,
      state_getter = state_getter,
      pending_species_setter = pending_species_setter
    ))

    chat
  }, error = function(e) {
    NULL
  })
}
