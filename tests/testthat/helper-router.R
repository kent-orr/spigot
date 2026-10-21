# The router used by the mount unit tests.
test_router <- function() {
  spigot_api() |>
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
    plumber::pr_get("/async", function() promises::promise_resolve(list(a = 1))) |>
    plumber::pr_get("/path", function(req) list(script = req$SCRIPT_NAME, path = req$PATH_INFO))
}

# Stands in for the running httpuv server: records each setStaticPath() list.
fake_server <- function() {
  calls <- list()
  list(
    setStaticPath = function(..., .list = NULL) calls[[length(calls) + 1L]] <<- .list,
    calls = function() calls
  )
}

# Run `app`'s onStart with `srv` as the running server, then the first
# event-loop tick, as shiny::runApp() does. Callbacks left by earlier tests
# run first, so they cannot reach `srv`.
start_with_server <- function(app, srv) {
  later::run_now()
  old <- shiny::getShinyOption("server", default = NULL)
  shiny::shinyOptions(server = srv)
  withr::defer(shiny::shinyOptions(server = old))
  app$onStart()
  later::run_now()
  invisible(srv)
}
