# The site's data and a helper for its pages. Shiny loads the files in R/ in
# alphabetical order, before app.R, so this one comes before pages-*.R.

car_data <- data.frame(model = rownames(datasets::mtcars), datasets::mtcars, row.names = NULL)
predictors <- c(
  wt = "Weight (1000 lbs)", hp = "Horsepower", disp = "Displacement (cu. in.)",
  qsec = "Quarter-mile time (s)", drat = "Rear axle ratio"
)

# A page of the site: its template and data. `key` tells the nav partial which
# link is the current page. The data never changes, so each page is rendered
# once and cached. The partials (head, nav, footer) come from the app.
page <- function(template, key, title, data = list()) {
  spigot::spigot_page(
    template,
    data = c(list(title = title, page = stats::setNames(list(TRUE), key)), data),
    cache = TRUE
  )
}
