# Fixture for test-page.R. Run by start_app() with spigot loaded; the working
# directory is this folder, so template and partial paths are relative to it.
library(shiny)

api <- spigot::spigot_api() |>
  plumber::pr_get("/hello", function() list(msg = "hi"))

plain <- "<html><head><title>{{title}}</title></head><body>{{> nav}}{{body}}</body></html>"

spigot::spigot_app(
  pages = list(
    "/" = spigot::spigot_page("index.html", data = list(title = "home"),
                              partials = list(nav = "nav.html")),
    "/about" = spigot::spigot_page(plain, data = list(title = "about"),
                                   partials = list(nav = "nav.html")),
    "/fluid" = fluidPage(tags$p("spigot-page-fluid")),
    "/fresh" = spigot::spigot_page(
      "<html><head></head><body>q={{q}} t={{t}}</body></html>",
      data = function(req) list(q = req$QUERY_STRING, t = format(Sys.time(), "%OS6"))
    ),
    "/cached" = spigot::spigot_page(
      "<html><head></head><body>t={{t}}</body></html>",
      data = list(t = format(Sys.time(), "%OS6")), cache = TRUE
    )
  ),
  api = api
)
