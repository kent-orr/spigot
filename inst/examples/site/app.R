# spigot "site" example: a small multi-page site about R's mtcars data.
#
# * Templates live in templates/, shared partials (the <head>, the nav bar and
#   the footer) in templates/partials/, and files the pages load in static/.
# * The /cars and /model sections are blueprints, defined in R/: each has its
#   own templates and static files. Shiny loads R/ before this file.
# * The /cars page is rendered in R with every row; its filter form then
#   calls the API and redraws the table in the browser.
# * The /model page calls an endpoint that bootstraps a regression in a
#   future worker, another R process, so the app keeps serving other tabs.
#
# Run it with spigot::run_example("site"). It needs the future package.
library(spigot)

# The fit endpoint hands its work to background R processes.
future::plan(future::multisession, workers = 2)
shiny::onStop(function() future::plan(future::sequential))

spigot_app(
  pages = list(
    "/" = page("index.html", "home", "Home", list(
      n = nrow(car_data),
      predictors = length(predictors)
    ))
  ),
  blueprints = list("/cars" = cars, "/model" = model),
  api = "api.R",
  templates = "templates",
  partials = "templates/partials",
  static = "static"
)
