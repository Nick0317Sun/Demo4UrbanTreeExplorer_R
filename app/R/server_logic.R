app_server <- function(input, output, session) {
  load_city_summary_data()

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
    shiny::updateSelectizeInput(
      session = session,
      inputId = "species",
      choices = species_choices_for_city(selected_city()),
      selected = ""
    )
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
}
