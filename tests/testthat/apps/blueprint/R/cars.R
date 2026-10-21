cars <- spigot::spigot_blueprint(
  pages = list(
    "/" = spigot::spigot_page("list.html", data = list(n = 32)),
    "/model" = spigot::spigot_page("model.html"),
    "/common" = spigot::spigot_page("common.html")
  ),
  api = "api/cars.R",
  templates = "templates/cars",
  partials = "templates/cars/partials",
  static = "static/cars"
)
