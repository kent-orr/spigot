# spigot "site" example: a small multi-page site about R's mtcars data.
#
# * Three pages, each a whisker template in pages/, sharing the partials in
#   partials/ (the <head>, the nav bar and the footer).
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

cars <- data.frame(model = rownames(datasets::mtcars), datasets::mtcars, row.names = NULL)
predictors <- c(
  wt = "Weight (1000 lbs)", hp = "Horsepower", disp = "Displacement (cu. in.)",
  qsec = "Quarter-mile time (s)", drat = "Rear axle ratio"
)

# A page of the site: its template, the shared partials, and its data. `key`
# tells the nav partial which link is the current page. The data never
# changes, so each page is rendered once and cached.
page <- function(file, key, title, data = list()) {
  spigot_page(
    file.path("pages", file),
    data = c(list(title = title, page = stats::setNames(list(TRUE), key)), data),
    partials = list(
      head = "partials/head.html",
      nav = "partials/nav.html",
      footer = "partials/footer.html"
    ),
    cache = TRUE
  )
}

spigot_app(
  pages = list(
    "/" = page("index.html", "home", "Home", list(
      n = nrow(cars),
      predictors = length(predictors)
    )),
    "/cars" = page("cars.html", "cars", "Cars", list(
      rows = unname(whisker::rowSplit(cars[c("model", "mpg", "cyl", "hp", "wt")]))
    )),
    "/model" = page("model.html", "model", "Model", list(
      predictors = Map(function(name, label) list(name = name, label = label),
                       names(predictors), unname(predictors), USE.NAMES = FALSE)
    ))
  ),
  api = "api.R"
)
