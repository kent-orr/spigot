# Integration fixture for test-mount.R. Run by start_app() with spigot loaded.
library(shiny)

if (requireNamespace("future", quietly = TRUE)) {
  future::plan(future::multisession, workers = 2)
}

api <- spigot::spigot_api() |>
  plumber::pr_get("/", function() list(root = TRUE)) |>
  plumber::pr_get("/items", function() 1:3) |>
  plumber::pr_post("/items", function(req, res) {
    res$status <- 201L
    req$body
  }) |>
  plumber::pr_put("/items/<id>", function(id) list(verb = "PUT", id = id)) |>
  plumber::pr_delete("/items/<id>", function(id) list(verb = "DELETE", id = id)) |>
  plumber::pr_get("/items-only-get", function() list(ok = TRUE)) |>
  plumber::pr_get("/boom", function() stop("kaboom")) |>
  plumber::pr_post("/echo-raw", function(req) req$bodyRaw,
                   serializer = plumber::serializer_octet(), parsers = "octet") |>
  plumber::pr_get("/slow", function() {
    promises::future_promise({
      Sys.sleep(1.5)
      list(ok = TRUE)
    })
  })

spigot::spigot_app(ui = fluidPage(tags$p("spigot-mount-fixture")), api = api)
