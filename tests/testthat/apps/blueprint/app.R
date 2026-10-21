# Fixture for test-blueprint.R: an app with one blueprint, `cars`, defined in
# R/cars.R, which Shiny loads before it sources this file.
spigot::spigot_app(
  pages = list(
    "/" = spigot::spigot_page("index.html"),
    "/common" = spigot::spigot_page("common.html")
  ),
  api = spigot::spigot_api() |> plumber::pr_get("/ping", function() list(ok = TRUE)),
  blueprints = list("/cars" = cars),
  templates = "templates",
  partials = "templates/partials"
)
