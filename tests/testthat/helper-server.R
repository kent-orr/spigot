# start_app(): run a Shiny app in a background R process on a random port and
# wait until it answers. `app` is an app directory or a self-contained
# function returning a shiny.appobj (it is serialised to the child process).

spigot_load_spec <- function() {
  path <- getNamespaceInfo("spigot", "path")
  dev <- requireNamespace("pkgload", quietly = TRUE) &&
    pkgload::is_dev_package("spigot")
  list(dev = dev, path = path)
}

start_app <- function(app, timeout = 20, env = parent.frame()) {
  testthat::skip_if_not_installed("callr")
  testthat::skip_if_not_installed("httr2")
  port <- httpuv::randomPort()
  if (is.character(app)) app <- normalizePath(app, mustWork = TRUE)
  proc <- callr::r_bg(
    function(app, port, load) {
      if (load$dev) {
        pkgload::load_all(load$path, quiet = TRUE, export_all = FALSE, helpers = FALSE)
      } else {
        library(spigot)
      }
      if (is.function(app)) app <- app()
      shiny::runApp(app, port = port, launch.browser = FALSE)
    },
    args = list(app = app, port = port, load = spigot_load_spec()),
    stdout = "|", stderr = "2>&1"
  )
  withr::defer(proc$kill(), envir = env)

  url <- sprintf("http://127.0.0.1:%d", port)
  deadline <- Sys.time() + timeout
  repeat {
    up <- tryCatch({
      httr2::req_perform(httr2::req_error(httr2::request(url), is_error = function(r) FALSE))
      TRUE
    }, error = function(e) FALSE)
    if (up) break
    if (!proc$is_alive()) {
      stop("app process died:\n", paste(proc$read_all_output_lines(), collapse = "\n"))
    }
    if (Sys.time() > deadline) stop("app did not start within ", timeout, " s")
    Sys.sleep(0.1)
  }
  list(url = url, proc = proc, port = port)
}

# Perform a request; never throws on HTTP status.
hit <- function(url, method = "GET", json = NULL, raw = NULL, type = NULL,
                headers = list()) {
  r <- httr2::request(url) |>
    httr2::req_method(method) |>
    httr2::req_error(is_error = function(r) FALSE)
  if (length(headers)) r <- httr2::req_headers(r, !!!headers)
  if (!is.null(json)) r <- httr2::req_body_json(r, json)
  if (!is.null(raw)) r <- httr2::req_body_raw(r, raw, type = type)
  httr2::req_perform(r)
}

hit_text <- function(resp) {
  if (!httr2::resp_has_body(resp)) return("")
  httr2::resp_body_string(resp)
}

# Open a Shiny session over the websocket, as a browser tab would, without a
# browser. Returns the session token and a close() that ends the session.
# Waits for the first flush after init, so the server function has run.
open_session <- function(url, timeout = 10, env = parent.frame()) {
  testthat::skip_if_not_installed("websocket")
  msgs <- character()
  ws <- websocket::WebSocket$new(paste0(sub("^http", "ws", url), "/websocket/"),
                                 autoConnect = FALSE)
  ws$onOpen(function(event) ws$send('{"method":"init","data":{}}'))
  ws$onMessage(function(event) msgs <<- c(msgs, event$data))
  ws$connect()

  close <- function() {
    if (ws$readyState() < 2L) ws$close()
    deadline <- Sys.time() + timeout
    while (ws$readyState() != 3L && Sys.time() < deadline) later::run_now(0.05)
    invisible()
  }
  withr::defer(close(), envir = env)

  deadline <- Sys.time() + timeout
  while (!any(grepl('"values"', msgs, fixed = TRUE))) {
    if (Sys.time() > deadline) stop("Shiny session did not start within ", timeout, " s")
    later::run_now(0.05)
  }
  config <- Filter(function(m) grepl('"config"', m, fixed = TRUE), msgs)[[1]]
  list(token = jsonlite::fromJSON(config)$config$sessionId, close = close)
}

# Poll `f()` until it is TRUE or `timeout` seconds pass; returns the last value.
eventually <- function(f, timeout = 1, interval = 0.05) {
  deadline <- Sys.time() + timeout
  repeat {
    ok <- isTRUE(f())
    if (ok || Sys.time() > deadline) return(ok)
    Sys.sleep(interval)
  }
}
