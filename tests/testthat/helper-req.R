# fake_req(): an environment shaped like the request httpuv hands to Shiny,
# so mount/session logic can be tested without a server.

fake_input <- function(raw) {
  pos <- 0L
  read <- function(l = -1L) {
    left <- length(raw) - pos
    n <- if (l < 0) left else min(l, left)
    if (n <= 0) return(raw(0))
    out <- raw[(pos + 1L):(pos + n)]
    pos <<- pos + n
    out
  }
  list(
    read = read,
    read_lines = function() {
      txt <- rawToChar(read())
      if (!nzchar(txt)) character(0) else strsplit(txt, "\r?\n")[[1]]
    },
    rewind = function() {
      pos <<- 0L
      invisible()
    }
  )
}

fake_req <- function(method = "GET", path = "/", query = "", body = NULL,
                     headers = list()) {
  content_type <- NULL
  if (is.list(body)) {
    body <- jsonlite::toJSON(body, auto_unbox = TRUE)
    content_type <- "application/json"
  }
  if (is.character(body)) body <- charToRaw(enc2utf8(paste(body, collapse = "")))
  if (is.null(body)) body <- raw(0)

  req <- new.env(parent = emptyenv())
  req$REQUEST_METHOD <- method
  req$SCRIPT_NAME <- ""
  req$PATH_INFO <- path
  req$QUERY_STRING <- if (nzchar(query) && !startsWith(query, "?")) paste0("?", query) else query
  req$SERVER_NAME <- "127.0.0.1"
  req$SERVER_PORT <- "1234"
  req$REMOTE_ADDR <- "127.0.0.1"
  req$REMOTE_PORT <- "50000"
  req$rook.version <- "1.1-0"
  req$rook.url_scheme <- "http"
  req$rook.input <- fake_input(body)

  # httpuv sets HTTP_<NAME> for every header, CONTENT_TYPE/CONTENT_LENGTH as
  # well, and HEADERS: a named character vector with lowercase names.
  all <- list(host = "127.0.0.1:1234")
  if (length(body)) all[["content-length"]] <- as.character(length(body))
  if (!is.null(content_type)) all[["content-type"]] <- content_type
  for (nm in names(headers)) all[[tolower(nm)]] <- headers[[nm]]
  for (nm in names(all)) {
    key <- toupper(gsub("-", "_", nm, fixed = TRUE))
    assign(paste0("HTTP_", key), all[[nm]], envir = req)
    if (key %in% c("CONTENT_TYPE", "CONTENT_LENGTH")) assign(key, all[[nm]], envir = req)
  }
  req$HEADERS <- unlist(all)
  req
}

# Body of an httpResponse as a string.
resp_text <- function(resp) {
  x <- resp$content
  if (is.raw(x)) rawToChar(x) else paste(x, collapse = "")
}

resp_json <- function(resp) jsonlite::fromJSON(resp_text(resp), simplifyVector = FALSE)

# Drive a promise to completion on the later loop and return its value
# (or rethrow its error).
await <- function(p, timeout = 5) {
  state <- new.env()
  state$done <- FALSE
  promises::then(
    p,
    onFulfilled = function(v) { state$value <- v; state$done <- TRUE },
    onRejected = function(e) { state$error <- e; state$done <- TRUE }
  )
  deadline <- Sys.time() + timeout
  while (!state$done && Sys.time() < deadline) later::run_now(0.05)
  if (!state$done) stop("promise did not settle within ", timeout, " s")
  if (!is.null(state$error)) stop(state$error)
  state$value
}
