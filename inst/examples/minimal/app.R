# spigot "minimal" example: one hand-written page calling a plumber API that
# runs inside this Shiny app, on the same origin and port.
#
# Run it with spigot::run_example("minimal").
library(spigot)

spigot_app(
  # A full HTML document. Shiny injects its scripts at {{ headContent() }}.
  ui = shiny::htmlTemplate("index.html", document_ = TRUE),
  # The API is a plain plumber file, served under /api.
  api = "api.R"
)
