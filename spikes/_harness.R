# M0 spike harness. Throwaway: spikes/ is deleted before M1 merges.
# Prototype of tests/testthat/helper-server.R.

# Start `app_fn(port)` (must return a shiny.appobj; self-contained, it is
# serialised to a fresh R process) and wait until GET / answers.
start_bg <- function(app_fn, timeout = 15) {
  port <- httpuv::randomPort()
  proc <- callr::r_bg(
    function(app_fn, port) {
      app <- app_fn(port)
      shiny::runApp(app, port = port, launch.browser = FALSE)
    },
    args = list(app_fn = app_fn, port = port),
    stdout = "|", stderr = "2>&1"
  )
  url <- sprintf("http://127.0.0.1:%d", port)
  deadline <- Sys.time() + timeout
  repeat {
    ok <- tryCatch({
      httr2::req_perform(httr2::req_error(httr2::request(url), is_error = \(r) FALSE))
      TRUE
    }, error = function(e) FALSE)
    if (ok) break
    if (!proc$is_alive()) stop("server died:\n", paste(proc$read_all_output_lines(), collapse = "\n"))
    if (Sys.time() > deadline) { proc$kill(); stop("server did not start in ", timeout, "s") }
    Sys.sleep(0.1)
  }
  list(url = url, proc = proc, port = port)
}

# Perform a request and never throw on HTTP status.
hit <- function(url, method = "GET", json = NULL, headers = list()) {
  r <- httr2::request(url) |> httr2::req_method(method) |>
    httr2::req_error(is_error = \(r) FALSE)
  if (length(headers)) r <- do.call(httr2::req_headers, c(list(r), headers))
  if (!is.null(json)) r <- httr2::req_body_json(r, json)
  httr2::req_perform(r)
}

body_text <- function(resp) {
  if (!httr2::resp_has_body(resp)) return("")
  httr2::resp_body_string(resp)
}

chrome_setup <- function() {
  chromote::local_chrome_version("latest-stable", binary = "chrome-headless-shell",
                                 quiet = TRUE, .local_envir = globalenv())
  chromote::set_chrome_args(c(chromote::default_chrome_args(), "--no-sandbox"))
}

# Evaluate JS in a chromote session, awaiting promises; returns the value.
js <- function(b, expr, timeout = 10) {
  r <- b$Runtime$evaluate(expr, awaitPromise = TRUE, returnByValue = TRUE,
                          timeout_ = timeout)
  if (!is.null(r$exceptionDetails)) stop("JS error: ", r$exceptionDetails$exception$description %||% r$exceptionDetails$text)
  r$result$value
}

check <- function(label, ok) {
  cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "PASS" else "FAIL", label))
  invisible(ok)
}
