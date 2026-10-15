# Integration fixture for test-session.R. Run by start_app() with spigot loaded.
library(shiny)

whoami <- function(req) {
  s <- spigot::spigot_session(req)
  list(token = if (is.null(s)) NULL else s$token)
}

api <- spigot::spigot_api() |>
  plumber::pr_get("/whoami", whoami) |>
  plumber::pr_post("/whoami", whoami)

spigot::spigot_app(
  ui = fluidPage(tags$p("spigot-session-fixture")),
  api = api,
  max_request_size = 1024
)
