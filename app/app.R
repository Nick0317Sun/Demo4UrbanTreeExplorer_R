source("R/utils.R")
source("R/data_access.R")
source("R/stats_helpers.R")
source("R/map_layers.R")
source("R/assistant_tools.R")
source("R/assistant_chat.R")
source("R/assistant_ui.R")
source("R/ui_panels.R")
source("R/server_logic.R")

shiny::shinyApp(
  ui = build_app_ui(),
  server = app_server
)
