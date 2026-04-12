build_app_ui <- function() {
  basemap_choices <- basemap_options()

  bslib::page_fillable(
    theme = app_theme(),
    fillable_mobile = TRUE,
    padding = 0,
    gap = 0,
    shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
      shiny::tags$script(src = "optional_js.js")
    ),
    shiny::div(
      class = "app-shell",
      shiny::div(
        class = "map-stage",
        mapgl::maplibreOutput("main_map", width = "100%", height = "100vh")
      ),
      shiny::div(
        class = "floating-panel top-right-panel",
        shiny::div(
          class = "panel-header",
          shiny::div(
            shiny::tags$span(class = "panel-kicker", "Urban Tree Explorer"),
            shiny::h2("Controls")
          ),
          shiny::tags$button(
            class = "panel-toggle",
            type = "button",
            `data-target` = "top-right-panel",
            `aria-expanded` = "true",
            "Collapse"
          )
        ),
        shiny::div(
          class = "panel-body",
          shiny::div(
            class = "control-block",
            shiny::tags$label(class = "control-label", `for` = "basemap", "Basemap"),
            shiny::selectInput(
              inputId = "basemap",
              label = NULL,
              choices = basemap_choices,
              selected = unname(basemap_choices[[1]])
            )
          ),
          shiny::div(
            class = "control-block",
            shiny::tags$label(class = "control-label", `for` = "city", "City"),
            shiny::selectizeInput(
              inputId = "city",
              label = NULL,
              choices = NULL,
              selected = "",
              options = list(placeholder = "Choose a city")
            )
          ),
          shiny::div(
            class = "control-block",
            shiny::tags$label(class = "control-label", `for` = "species", "Species"),
            shiny::selectizeInput(
              inputId = "species",
              label = NULL,
              choices = c("Select a city first" = ""),
              selected = "",
              options = list(placeholder = "All species")
            )
          ),
          shiny::uiOutput("city_stats_ui"),
          shiny::div(
            class = "chart-block",
            shiny::plotOutput("species_chart", height = "240px")
          )
        )
      ),
      shiny::div(
        class = "floating-panel bottom-right-panel",
        shiny::div(
          class = "panel-header",
          shiny::div(
            shiny::tags$span(class = "panel-kicker", "Placeholder"),
            shiny::h2("Data Assistant")
          ),
          shiny::tags$button(
            class = "panel-toggle",
            type = "button",
            `data-target` = "bottom-right-panel",
            `aria-expanded` = "true",
            "Collapse"
          )
        ),
        shiny::div(
          class = "panel-body",
          shiny::p(
            class = "assistant-copy",
            "Coming later. Phase 3 keeps the assistant panel visible but non-functional."
          ),
          shiny::tags$input(
            class = "assistant-input",
            type = "text",
            placeholder = "Assistant input will be enabled in a later phase",
            disabled = "disabled"
          )
        )
      )
    )
  )
}
