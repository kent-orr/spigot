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
