assistant_json <- function(x) {
  jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null")
}

assistant_normalize_string <- function(x) {
  tolower(trimws(as.character(x %||% "")))
}

assistant_city_match <- function(city) {
  city_value <- assistant_normalize_string(city)
  city_summary <- load_city_summary_data()

  if (!nzchar(city_value)) {
    return(list(ok = FALSE, message = "City name is required."))
  }

  exact_idx <- which(
    assistant_normalize_string(city_summary$city) == city_value |
      assistant_normalize_string(city_summary$city_key) == city_value
  )
  if (length(exact_idx) == 1) {
    row <- city_summary[exact_idx, , drop = FALSE]
    return(list(ok = TRUE, city_key = row$city_key[[1]], city = row$city[[1]], state = row$state[[1]]))
  }

  partial_idx <- which(grepl(city_value, assistant_normalize_string(city_summary$city), fixed = TRUE))
  if (length(partial_idx) == 1) {
    row <- city_summary[partial_idx, , drop = FALSE]
    return(list(ok = TRUE, city_key = row$city_key[[1]], city = row$city[[1]], state = row$state[[1]]))
  }

  if (length(partial_idx) > 1) {
    choices <- paste(city_summary$city[partial_idx], city_summary$state[partial_idx], sep = ", ")
    return(list(ok = FALSE, message = paste("City is ambiguous. Try one of:", paste(choices, collapse = "; "))))
  }

  list(ok = FALSE, message = paste0("No city matched '", city, "'."))
}

assistant_species_match <- function(city_key, species) {
  species_value <- assistant_normalize_string(species)
  choices <- sort(unique(stats::na.omit(as.character(load_city_tree_data(city_key)$species_display))))

  if (!nzchar(species_value)) {
    return(list(ok = FALSE, message = "Species name is required."))
  }

  exact_idx <- which(assistant_normalize_string(choices) == species_value)
  if (length(exact_idx) == 1) {
    return(list(ok = TRUE, species = choices[[exact_idx]]))
  }

  partial_idx <- which(grepl(species_value, assistant_normalize_string(choices), fixed = TRUE))
  if (length(partial_idx) == 1) {
    return(list(ok = TRUE, species = choices[[partial_idx]]))
  }

  if (length(partial_idx) > 1) {
    suggestions <- head(choices[partial_idx], 5)
    return(list(ok = FALSE, message = paste("Species is ambiguous. Try one of:", paste(suggestions, collapse = "; "))))
  }

  list(ok = FALSE, message = paste0("No species matched '", species, "' in that city."))
}

assistant_bbox_filter <- function(tbl, xmin, ymin, xmax, ymax) {
  tbl[
    tbl$has_valid_coordinates &
      tbl$longitude >= xmin &
      tbl$longitude <= xmax &
      tbl$latitude >= ymin &
      tbl$latitude <= ymax,
    ,
    drop = FALSE
  ]
}

assistant_app_state <- function(state_getter) {
  state <- state_getter()
  state$selected_city <- state$selected_city %||% ""
  state$selected_species <- state$selected_species %||% ""
  state$intersecting_cities <- state$intersecting_cities %||% character()
  state
}

build_assistant_tools <- function(session, state_getter, pending_species_setter = function(value) NULL) {
  get_national_summary <- function() {
    city_summary <- load_city_summary_data()
    ranked <- city_summary[order(city_summary$n_trees, decreasing = TRUE), , drop = FALSE]
    payload <- list(
      total_cities = nrow(city_summary),
      total_trees = sum(city_summary$n_trees),
      total_species = sum(city_summary$n_species),
      top_cities = utils::head(
        lapply(seq_len(min(5, nrow(ranked))), function(i) {
          row <- ranked[i, , drop = FALSE]
          list(city = row$city[[1]], state = row$state[[1]], trees = row$n_trees[[1]], species = row$n_species[[1]])
        }),
        5
      )
    )
    assistant_json(payload)
  }

  get_city_summary <- function(city) {
    matched <- assistant_city_match(city)
    if (!matched$ok) {
      return(matched$message)
    }

    row <- get_city_summary_row(matched$city_key)
    assistant_json(list(
      city = row$city[[1]],
      state = row$state[[1]],
      total_trees = row$n_trees[[1]],
      valid_coordinate_trees = row$n_valid_coordinates[[1]],
      species_count = row$n_species[[1]],
      top_species = c(row$top_species_1[[1]], row$top_species_2[[1]], row$top_species_3[[1]]),
      marker_lon = row$marker_lon[[1]],
      marker_lat = row$marker_lat[[1]],
      view_lon = row$view_lon[[1]],
      view_lat = row$view_lat[[1]],
      default_zoom = row$default_zoom[[1]]
    ))
  }

  get_top_species <- function(city, n = 10L) {
    matched <- assistant_city_match(city)
    if (!matched$ok) {
      return(matched$message)
    }

    n <- max(1L, min(as.integer(n %||% 10L), 20L))
    top_species <- top_species_for_city(matched$city_key)
    if (n > nrow(top_species)) {
      city_data <- load_city_tree_data(matched$city_key)
      top_species <- dplyr::count(
        city_data[!is.na(city_data$species_display) & city_data$species_display != "Unknown species", , drop = FALSE],
        species_display,
        sort = TRUE,
        name = "tree_count"
      )
      top_species <- utils::head(top_species, n)
    } else {
      top_species <- utils::head(top_species, n)
    }

    assistant_json(list(
      city = matched$city,
      state = matched$state,
      top_species = lapply(seq_len(nrow(top_species)), function(i) {
        list(
          species = top_species$species_display[[i]],
          tree_count = as.integer(top_species$tree_count[[i]])
        )
      })
    ))
  }

  get_species_summary <- function(city, species) {
    matched <- assistant_city_match(city)
    if (!matched$ok) {
      return(matched$message)
    }

    species_match <- assistant_species_match(matched$city_key, species)
    if (!species_match$ok) {
      return(species_match$message)
    }

    city_data <- filtered_city_tree_data(matched$city_key, species = species_match$species)
    city_row <- get_city_summary_row(matched$city_key)

    assistant_json(list(
      city = matched$city,
      state = matched$state,
      species = species_match$species,
      tree_count = nrow(city_data),
      share_of_city_trees = round(nrow(city_data) / city_row$n_trees[[1]], 4),
      has_valid_coordinates = sum(city_data$has_valid_coordinates),
      top_common_name = species_match$species
    ))
  }

  get_viewport_summary <- function(xmin, ymin, xmax, ymax, city = NULL, species = NULL) {
    bbox <- list(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax)
    city_keys <- character()

    if (!is.null(city) && nzchar(city)) {
      matched <- assistant_city_match(city)
      if (!matched$ok) {
        return(matched$message)
      }
      city_keys <- matched$city_key
    } else {
      city_keys <- intersecting_cities_for_bbox(bbox, max_cities = 2L)
    }

    if (length(city_keys) == 0) {
      return("The viewport does not clearly intersect a supported city extent.")
    }

    species_value <- if (!is.null(species) && nzchar(species)) species else ""
    summaries <- lapply(city_keys, function(city_key) {
      city_row <- get_city_summary_row(city_key)
      city_data <- filtered_city_tree_data(city_key, species = species_value)
      city_data <- assistant_bbox_filter(city_data, xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax)
      list(
        city = city_row$city[[1]],
        state = city_row$state[[1]],
        tree_count = nrow(city_data),
        species_count = dplyr::n_distinct(city_data$species_key[!is.na(city_data$species_key) & city_data$species_key != "unknown_species"])
      )
    })

    assistant_json(list(
      bbox = bbox,
      city_count = length(city_keys),
      species_filter = if (nzchar(species_value)) species_value else NULL,
      cities = summaries
    ))
  }

  fly_to_city <- function(city) {
    matched <- assistant_city_match(city)
    if (!matched$ok) {
      return(matched$message)
    }

    pending_species_setter(NULL)
    shiny::updateSelectizeInput(session, "city", selected = matched$city_key)
    paste0("Moved the map to ", matched$city, ", ", matched$state, ".")
  }

  set_species_filter <- function(species) {
    state <- assistant_app_state(state_getter)
    target_city <- state$selected_city

    if (!nzchar(target_city) && nzchar(state$active_city %||% "")) {
      target_city <- state$active_city
    }
    if (!nzchar(target_city)) {
      return("Select or fly to a city first, then I can set a species filter.")
    }

    species_match <- assistant_species_match(target_city, species)
    if (!species_match$ok) {
      return(species_match$message)
    }

    pending_species_setter(species_match$species)
    if (!identical(state$selected_city, target_city)) {
      shiny::updateSelectizeInput(session, "city", selected = target_city)
    } else {
      shiny::updateSelectizeInput(
        session,
        "species",
        choices = species_choices_for_city(target_city),
        selected = species_match$species
      )
      pending_species_setter(NULL)
    }

    paste0("Set the species filter to ", species_match$species, ".")
  }

  clear_city_selection <- function() {
    pending_species_setter(NULL)
    shiny::updateSelectizeInput(session, "city", selected = "")
    shiny::updateSelectizeInput(session, "species", choices = c("Select a city first" = ""), selected = "")
    "Cleared the city selection and returned to national view controls."
  }

  clear_species_filter <- function() {
    pending_species_setter(NULL)
    state <- assistant_app_state(state_getter)
    shiny::updateSelectizeInput(
      session,
      "species",
      choices = species_choices_for_city(state$selected_city),
      selected = ""
    )
    "Cleared the species filter."
  }

  list(
    ellmer::tool(
      get_national_summary,
      name = "get_national_summary",
      description = "Return national totals and the largest cities in the processed runtime dataset."
    ),
    ellmer::tool(
      get_city_summary,
      name = "get_city_summary",
      description = "Return the summary for one city, including tree totals, species count, and overview center.",
      arguments = list(
        city = ellmer::type_string("City name or city key, like 'San Francisco' or 'san_francisco'.")
      )
    ),
    ellmer::tool(
      get_top_species,
      name = "get_top_species",
      description = "Return the top species for one city.",
      arguments = list(
        city = ellmer::type_string("City name or city key."),
        n = ellmer::type_integer("How many species to return. Keep this small, usually 10.")
      )
    ),
    ellmer::tool(
      get_species_summary,
      name = "get_species_summary",
      description = "Return the count and share for a species within a city.",
      arguments = list(
        city = ellmer::type_string("City name or city key."),
        species = ellmer::type_string("Species display name to summarize.")
      )
    ),
    ellmer::tool(
      get_viewport_summary,
      name = "get_viewport_summary",
      description = "Summarize trees inside a viewport bounding box, optionally constrained to a city or species.",
      arguments = list(
        xmin = ellmer::type_number("Viewport minimum longitude."),
        ymin = ellmer::type_number("Viewport minimum latitude."),
        xmax = ellmer::type_number("Viewport maximum longitude."),
        ymax = ellmer::type_number("Viewport maximum latitude."),
        city = ellmer::type_string("Optional city name or city key. Use an empty string to omit."),
        species = ellmer::type_string("Optional species display name. Use an empty string to omit.")
      )
    ),
    ellmer::tool(
      fly_to_city,
      name = "fly_to_city",
      description = "Select a city in the app so the map flies there and the stats update.",
      arguments = list(
        city = ellmer::type_string("City name or city key.")
      )
    ),
    ellmer::tool(
      set_species_filter,
      name = "set_species_filter",
      description = "Set the species filter for the current or active city context.",
      arguments = list(
        species = ellmer::type_string("Species display name to select.")
      )
    ),
    ellmer::tool(
      clear_city_selection,
      name = "clear_city_selection",
      description = "Clear the selected city and return to national view controls."
    ),
    ellmer::tool(
      clear_species_filter,
      name = "clear_species_filter",
      description = "Clear the selected species filter."
    )
  )
}
