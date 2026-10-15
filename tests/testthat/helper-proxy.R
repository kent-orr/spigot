# start_proxy(): a reverse proxy that serves an app under a subpath, the way
# Shiny Server or Posit Connect do. Requests to `{prefix}/...` are forwarded
# to `upstream` with the prefix stripped, websockets included. Like most
# proxies it rewrites Host and sets X-Forwarded-Host.

start_proxy <- function(upstream, prefix = "/sub/app", timeout = 20, env = parent.frame()) {
  testthat::skip_if_not_installed("curl")
  testthat::skip_if_not_installed("websocket")
  upstream <- sub("/+$", "", upstream)
  port <- httpuv::randomPort()
  proc <- callr::r_bg(run_proxy, args = list(upstream = upstream, prefix = prefix, port = port),
                      stdout = "|", stderr = "2>&1")
  withr::defer(proc$kill(), envir = env)

  url <- sprintf("http://127.0.0.1:%d%s/", port, prefix)
  deadline <- Sys.time() + timeout
  repeat {
    up <- tryCatch(httr2::resp_status(hit(url)) == 200L, error = function(e) FALSE)
    if (up) break
    if (!proc$is_alive()) {
      stop("proxy process died:\n", paste(proc$read_all_output_lines(), collapse = "\n"))
    }
    if (Sys.time() > deadline) stop("proxy did not start within ", timeout, " s")
    Sys.sleep(0.1)
  }
  list(url = url, proc = proc)
}

# Runs in the child process.
run_proxy <- function(upstream, prefix, port) {
  hop <- c("connection", "keep-alive", "transfer-encoding", "content-length",
           "content-encoding", "upgrade", "host")

  strip <- function(path) {
    if (!startsWith(path, paste0(prefix, "/"))) return(NULL)
    substring(path, nchar(prefix) + 1L)
  }

  call <- function(req) {
    path <- req$PATH_INFO
    if (identical(path, prefix)) {
      return(list(status = 301L, headers = list(Location = paste0(prefix, "/")), body = ""))
    }
    rest <- strip(path)
    if (is.null(rest)) {
      return(list(status = 404L, headers = list(`Content-Type` = "text/plain"),
                  body = "not under the proxy prefix"))
    }
    h <- curl::new_handle(customrequest = req$REQUEST_METHOD, followlocation = FALSE)
    fwd <- as.list(req$HEADERS)
    fwd <- fwd[!tolower(names(fwd)) %in% c(hop, "accept-encoding")]
    fwd[["X-Forwarded-Host"]] <- req$HTTP_HOST
    do.call(curl::handle_setheaders, c(list(h), fwd))
    body <- req$rook.input$read()
    if (length(body)) curl::handle_setopt(h, post = TRUE, postfieldsize = length(body),
                                          copypostfields = body)
    res <- curl::curl_fetch_memory(paste0(upstream, rest, req$QUERY_STRING), handle = h)
    headers <- curl::parse_headers_list(res$headers)
    headers <- headers[!tolower(names(headers)) %in% hop]
    list(status = res$status_code, headers = headers, body = res$content)
  }

  onWSOpen <- function(ws) {
    rest <- strip(ws$request$PATH_INFO) %||% ws$request$PATH_INFO
    target <- paste0(sub("^http", "ws", upstream), rest, ws$request$QUERY_STRING %||% "")
    up <- websocket::WebSocket$new(target, autoConnect = FALSE)
    pending <- list()
    open <- FALSE
    up$onOpen(function(event) {
      open <<- TRUE
      for (m in pending) up$send(m)
      pending <<- list()
    })
    up$onMessage(function(event) ws$send(event$data))
    up$onClose(function(event) try(ws$close(), silent = TRUE))
    ws$onMessage(function(binary, message) {
      if (open) up$send(message) else pending[[length(pending) + 1L]] <<- message
    })
    ws$onClose(function() try(up$close(), silent = TRUE))
    up$connect()
  }

  `%||%` <- function(x, y) if (is.null(x)) y else x
  httpuv::runServer("127.0.0.1", port, list(call = call, onWSOpen = onWSOpen))
}
