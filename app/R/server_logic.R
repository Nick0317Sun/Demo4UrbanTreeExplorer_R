app_server <- function(input, output, session) {
  load_city_summary_data()
  assistant_intro_messages <- function(model_name = NULL, switched = FALSE) {
    text <- if (isTRUE(switched) && nzchar(model_name %||% "")) {
      paste0("Assistant reset on model switch. Current model: ", model_name, ".")
    } else {
      "Ask about national totals, a city, a species, map actions, or a general question."
    }

    list(list(role = "assistant", text = text))
  }

  assistant_messages <- shiny::reactiveVal(assistant_intro_messages())
  assistant_busy <- shiny::reactiveVal(FALSE)
  pending_species_selection <- shiny::reactiveVal(NULL)
  model_catalog <- assistant_fetch_model_catalog()
  assistant_model_choices <- stats::setNames(model_catalog$models$id, model_catalog$models$label)
  initial_model <- if (assistant_default_model() %in% model_catalog$models$id) {
    assistant_default_model()
  } else {
    model_catalog$models$id[[1]]
  }
  assistant_model <- shiny::reactiveVal(initial_model)
  assistant_chat <- shiny::reactiveVal(NULL)

  shiny::updateSelectizeInput(
    session = session,
    inputId = "city",
    choices = city_choices(),
    selected = ""
  )

  selected_city <- shiny::reactive({
    input$city %||% ""
  })

  selected_species <- shiny::reactive({
    input$species %||% ""
  })

  current_zoom <- shiny::reactive({
    input$main_map_zoom %||% national_view()$zoom
  })

  current_bbox <- shiny::reactive({
    input$main_map_bbox %||% NULL
  })

  current_center <- shiny::reactive({
    input$main_map_center %||% NULL
  })

  current_state <- function() {
    navigation <- list(
      zoom = current_zoom(),
      bbox = current_bbox(),
      center = current_center()
    )
    context <- auto_city_context(
      selected_city = selected_city(),
      zoom_value = navigation$zoom,
      bbox = navigation$bbox,
      center = navigation$center
    )

    list(
      selected_city = selected_city(),
      selected_species = selected_species(),
      zoom = navigation$zoom,
      bbox = navigation$bbox,
      center = navigation$center,
      active_city = context$active_city %||% "",
      intersecting_cities = context$intersecting_keys %||% character()
    )
  }

  rebuild_assistant_chat <- function(model_name, reset_messages = FALSE) {
    assistant_busy(FALSE)
    assistant_chat(create_session_assistant_chat(
      session = session,
      state_getter = current_state,
      pending_species_setter = pending_species_selection,
      model = model_name
    ))
    if (isTRUE(reset_messages)) {
      assistant_messages(assistant_intro_messages(model_name, switched = TRUE))
    }
  }

  assistant_ready <- shiny::reactive({
    !is.null(assistant_chat())
  })

  rebuild_assistant_chat(initial_model)

  update_assistant_controls <- function() {
    disabled <- !assistant_is_available() || !assistant_ready() || assistant_busy()
    session$sendCustomMessage("assistant:set-state", list(
      disabled = disabled,
      busy = assistant_busy(),
      placeholder = if (disabled && !assistant_busy()) {
        "Assistant is unavailable."
      } else {
        "Ask about urban tree data, control the map, or ask a general question."
      },
      button_label = if (assistant_busy()) "Working..." else "Send"
    ))
  }

  debounced_navigation <- shiny::debounce(
    shiny::reactive({
      list(
        zoom = current_zoom(),
        bbox = current_bbox(),
        center = current_center()
      )
    }),
    millis = 160
  )

  last_map_signature <- shiny::reactiveVal(NULL)

  shiny::observeEvent(selected_city(), {
    requested_species <- pending_species_selection()
    species_choices <- species_choices_for_city(selected_city())
    selected_value <- if (!is.null(requested_species) && requested_species %in% unname(species_choices)) {
      requested_species
    } else {
      ""
    }

    shiny::updateSelectizeInput(
      session = session,
      inputId = "species",
      choices = species_choices,
      selected = selected_value
    )
    pending_species_selection(NULL)
  }, ignoreInit = FALSE)

  shiny::observeEvent(selected_city(), {
    focus_map_for_city_selection(selected_city())
  }, ignoreInit = TRUE)

  output$main_map <- mapgl::renderMaplibre({
    default_map_widget(style_url = input$basemap %||% unname(basemap_options()[[1]]))
  })

  shiny::observeEvent(input$basemap, {
    mapgl::maplibre_proxy("main_map") |>
      mapgl::set_style(input$basemap, preserve_layers = TRUE)
  }, ignoreInit = TRUE)

  shiny::observeEvent(
    list(selected_city(), selected_species(), debounced_navigation()),
    {
      navigation <- debounced_navigation()
      signature <- map_content_signature(
        selected_city = selected_city(),
        species = selected_species(),
        zoom_value = navigation$zoom,
        bbox = navigation$bbox,
        center = navigation$center
      )

      if (identical(signature, last_map_signature())) {
        return(invisible(NULL))
      }
      last_map_signature(signature)

      update_selected_city_map(
        selected_city(),
        species = selected_species(),
        zoom_value = navigation$zoom,
        bbox = navigation$bbox,
        center = navigation$center
      )
    },
    ignoreInit = FALSE
  )

  output$city_stats_ui <- shiny::renderUI({
    stats <- build_city_stats(selected_city(), species = selected_species())

    shiny::div(
      class = "stats-block",
      shiny::div(
        class = "stats-heading",
        shiny::tags$span(class = "panel-kicker", "Statistics"),
        shiny::h3(stats$city_label)
      ),
      shiny::div(
        class = "stats-grid",
        shiny::div(
          class = "stat-tile",
          shiny::span("Trees"),
          shiny::strong(format_count(stats$total_trees))
        ),
        shiny::div(
          class = "stat-tile",
          shiny::span(stats$species_label),
          shiny::strong(format_count(stats$species_count))
        ),
        shiny::div(
          class = "stat-tile stat-tile-wide",
          shiny::span(if (is.null(stats$selected_species)) "Top species" else "Selected species"),
          shiny::strong(if (is.null(stats$selected_species)) stats$top_species else stats$selected_species)
        )
      ),
      if (!is.null(stats$selected_species_trees)) {
        shiny::div(
          class = "species-summary",
          shiny::span("Filtered tree count"),
          shiny::strong(format_count(stats$selected_species_trees))
        )
      }
    )
  })

  output$species_chart <- shiny::renderPlot({
    shiny::req(nzchar(selected_city()))
    chart <- build_species_chart(selected_city(), species = selected_species())
    shiny::validate(shiny::need(!is.null(chart), "Select a city to view species ranks."))
    chart
  }, res = 110)

  output$assistant_status_ui <- shiny::renderUI({
    if (!requireNamespace("ellmer", quietly = TRUE)) {
      return(shiny::div(
        class = "assistant-status assistant-status-error",
        "ellmer is not available in this container."
      ))
    }

    if (!nzchar(Sys.getenv("NRP_API_KEY"))) {
      return(shiny::div(
        class = "assistant-status assistant-status-error",
        "Set NRP_API_KEY in the environment to enable the assistant."
      ))
    }

    if (!assistant_ready()) {
      return(shiny::div(
        class = "assistant-status assistant-status-error",
        "The assistant client could not be initialized for this session."
      ))
    }

    if (assistant_busy()) {
      return(shiny::div(
        class = "assistant-status assistant-status-live",
        "Assistant is thinking..."
      ))
    }

    shiny::div(
      class = "assistant-status assistant-status-ready",
      paste0(
        "Model: ", assistant_model(),
        if (isTRUE(model_catalog$fallback_used)) " (fallback list)" else ""
      ),
      if (!is.null(model_catalog$error) && nzchar(model_catalog$error)) {
        shiny::tags$div(class = "assistant-status-note", "Model list retrieval failed; using fallback choices.")
      }
    )
  })

  output$assistant_model_ui <- shiny::renderUI({
    shiny::div(
      class = "assistant-model-block",
      shiny::tags$label(class = "control-label", `for` = "assistant_model", "Model"),
      shiny::selectInput(
        inputId = "assistant_model",
        label = NULL,
        choices = assistant_model_choices,
        selected = assistant_model()
      )
    )
  })

  output$assistant_links_ui <- shiny::renderUI({
    links <- assistant_external_links()
    shiny::div(
      class = "assistant-links",
      lapply(links, function(link) {
        shiny::tags$a(
          class = "assistant-link-btn",
          href = link$href,
          target = "_blank",
          rel = "noopener noreferrer",
          shiny::tags$span(
            class = "assistant-link-icon",
            `aria-hidden` = "true",
            if (identical(link$icon %||% "", "leaf")) {
              shiny::tags$svg(
                viewBox = "0 0 24 24",
                fill = "none",
                stroke = "currentColor",
                stroke_width = "1.8",
                stroke_linecap = "round",
                stroke_linejoin = "round",
                shiny::tags$path(d = "M19 5c-6.5.2-10.7 2.7-12.9 7.4C4.8 15.3 5 18.7 5 20c1.3 0 4.7.2 7.6-1.1C17.3 16.7 19.8 12.5 20 6c0-.3-.1-.6-.3-.7C19.6 5.1 19.3 5 19 5Z"),
                shiny::tags$path(d = "M8 16c2.5-1.9 5.1-3.9 8-6")
              )
            } else {
              shiny::tags$span("\u2197")
            }
          ),
          shiny::tags$span(class = "assistant-link-label", link$label)
        )
      })
    )
  })

  output$assistant_messages_ui <- shiny::renderUI({
    messages <- assistant_messages()
    shiny::tagList(lapply(messages, function(message) {
      shiny::div(
        class = paste("assistant-message", paste0("assistant-message-", message$role)),
        shiny::tags$span(
          class = "assistant-message-role",
          switch(
            message$role,
            user = "You",
            assistant = "Assistant",
            error = "Error",
            "Assistant"
          )
        ),
        shiny::div(class = "assistant-message-text", message$text)
      )
    }))
  })

  shiny::observeEvent(assistant_messages(), {
    session$onFlushed(function() {
      session$sendCustomMessage("assistant:scroll-history", list(force = TRUE))
    }, once = TRUE)
  }, ignoreInit = FALSE)

  shiny::observe({
    assistant_busy()
    update_assistant_controls()
  })

  shiny::observe({
    assistant_ready()
    update_assistant_controls()
  })

  shiny::observeEvent(input$assistant_model, {
    requested_model <- input$assistant_model %||% initial_model
    if (assistant_busy()) {
      return(invisible(NULL))
    }
    if (!requested_model %in% model_catalog$models$id) {
      requested_model <- initial_model
    }
    if (identical(requested_model, assistant_model())) {
      return(invisible(NULL))
    }

    assistant_model(requested_model)
    rebuild_assistant_chat(requested_model, reset_messages = TRUE)
  }, ignoreInit = TRUE)

  submit_assistant_message <- function(message_text = NULL) {
    if (!assistant_is_available() || !assistant_ready()) {
      return(invisible(NULL))
    }
    if (assistant_busy()) {
      return(invisible(NULL))
    }

    user_message <- trimws(message_text %||% input$assistant_input %||% "")
    if (!nzchar(user_message)) {
      return(invisible(NULL))
    }

    assistant_messages(c(
      assistant_messages(),
      list(list(role = "user", text = user_message))
    ))
    assistant_busy(TRUE)
    shiny::updateTextAreaInput(session, "assistant_input", value = "")

    prompt <- assistant_prompt(user_message, current_state())

    tryCatch({
      promises::then(
        assistant_chat()$chat_async(prompt, tool_mode = "sequential"),
        onFulfilled = function(response) {
          assistant_messages(c(
            assistant_messages(),
            list(list(role = "assistant", text = trimws(as.character(response))))
          ))
          assistant_busy(FALSE)
          session$sendCustomMessage("assistant:focus-input", list())
        },
        onRejected = function(err) {
          error_text <- conditionMessage(err)
          if (!nzchar(error_text)) {
            error_text <- "The assistant request failed."
          }

          assistant_messages(c(
            assistant_messages(),
            list(list(role = "error", text = error_text))
          ))
          assistant_busy(FALSE)
          session$sendCustomMessage("assistant:focus-input", list())
          NULL
        }
      )
    }, error = function(err) {
      error_text <- conditionMessage(err)
      if (!nzchar(error_text)) {
        error_text <- "The assistant request failed."
      }

      assistant_messages(c(
        assistant_messages(),
        list(list(role = "error", text = error_text))
      ))
      assistant_busy(FALSE)
      session$sendCustomMessage("assistant:focus-input", list())
      NULL
    })
  }

  shiny::observeEvent(input$assistant_send, {
    submit_assistant_message()
  })

  shiny::observeEvent(input$assistant_submit, {
    submit_assistant_message(message_text = input$assistant_submit$text %||% "")
  }, ignoreInit = TRUE)
}
