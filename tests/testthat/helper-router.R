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
