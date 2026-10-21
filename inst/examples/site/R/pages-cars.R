# The cars section: its page renders every row in R; static/cars/cars.js
# filters them through the API. Mounted at /cars in app.R.
cars <- spigot::spigot_blueprint(
  pages = page("cars.html", "cars", "Cars", list(
    rows = unname(whisker::rowSplit(car_data[c("model", "mpg", "cyl", "hp", "wt")]))
  )),
  templates = "templates/cars",
  static = "static/cars"
)
