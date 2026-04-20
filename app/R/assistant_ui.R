assistant_panel_ui <- function() {
  shiny::div(
    class = "floating-panel bottom-right-panel assistant-panel",
    shiny::div(
      class = "panel-header",
      shiny::div(
        shiny::tags$span(class = "panel-kicker", "Assistant v0"),
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
      class = "panel-body assistant-panel-body",
      shiny::uiOutput("assistant_status_ui"),
      shiny::uiOutput("assistant_model_ui"),
      shiny::div(
        class = "assistant-history",
        id = "assistant-history",
        shiny::uiOutput("assistant_messages_ui")
      ),
      shiny::div(
        class = "assistant-composer",
        shiny::textAreaInput(
          inputId = "assistant_input",
          label = NULL,
          width = "100%",
          rows = 3,
          resize = "none",
          placeholder = "Ask about urban tree data, control the map, or ask a general question."
        ),
        shiny::div(
          class = "assistant-send-row",
          shiny::actionButton(
            inputId = "assistant_send",
            label = "Send",
            class = "assistant-send-btn"
          )
        )
      ),
      shiny::uiOutput("assistant_links_ui")
    )
  )
}
