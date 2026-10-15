# e2e fixture for test-client.R. Run by start_app() with spigot loaded.
# spigot_app() attaches spigot.js to the page; the page adds nothing else
# except a call made while the page is still parsing, before the Shiny
# session exists.
library(shiny)

echo_query <- function(req) {
  list(
    query = req$QUERY_STRING,
    session = req$HTTP_X_SPIGOT_SESSION,
    custom = req$HTTP_X_CUSTOM,
    accept = req$HTTP_ACCEPT
  )
}

# Returns the request body byte for byte, so the client sees exactly what it
# sent, plus the Content-Type the server received.
echo_json <- function(req, res) {
  res$setHeader("Content-Type", "application/json")
  res$setHeader("X-Seen-Content-Type", req$HTTP_CONTENT_TYPE %||% "")
  res$body <- rawToChar(req$bodyRaw)
  res
}

echo_method <- function(req) {
  list(method = req$REQUEST_METHOD, query = req$QUERY_STRING,
       body = rawToChar(req$bodyRaw %||% raw(0)))
}

fail <- function(res, status = "500", json = "true") {
  res$status <- as.integer(status)
  if (identical(json, "true")) return(list(error = paste("failed with", status)))
  res$serializer <- plumber::serializer_text()
  "plain failure"
}

slow <- function(ms = "1000") {
  secs <- as.numeric(ms) / 1000
  promises::promise(function(resolve, reject) {
    later::later(function() resolve(list(waited = secs)), delay = secs)
  })
}

api <- spigot::spigot_api() |>
  plumber::pr_get("/echo-query", echo_query) |>
  plumber::pr_post("/echo-json", echo_json) |>
  plumber::pr_put("/echo-method", echo_method) |>
  plumber::pr_delete("/echo-method", echo_method) |>
  plumber::pr_get("/fail", fail) |>
  plumber::pr_get("/no-content", function(res) {
    res$status <- 204L
    res$body <- NULL
    res
  }) |>
  plumber::pr_get("/slow", slow)

early <- "
  window.early = {sessionAtCall: spigot.sessionId, threw: null};
  try {
    window.early.result = spigot.get('echo-query', {early: 1});
  } catch (e) {
    window.early.threw = String(e);
  }
"

spigot::spigot_app(
  ui = tagList(tags$p("spigot-client-fixture"), tags$script(HTML(early))),
  api = api
)
