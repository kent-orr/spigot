# Convert plumber's Rook response, list(status, headers, body), into the
# httpResponse Shiny expects from an httpHandler.
rook_to_httpResponse <- function(res) {
  headers <- as.list(res$headers %||% list())
  body <- res$body

  ct_i <- which(tolower(names(headers)) == "content-type")
  content_type <- if (length(ct_i)) {
    headers[[ct_i[1]]]
  } else if (is.raw(body)) {
    "application/octet-stream"
  } else {
    "text/plain"
  }
  if (length(ct_i)) headers <- headers[-ct_i]

  content <- if (is.null(body)) {
    ""
  } else if (is.raw(body)) {
    body
  } else {
    enc2utf8(paste(as.character(body), collapse = ""))
  }

  api_response(res$status, content_type, content, headers)
}

# shiny::httpResponse() with `X-Content-Type-Options: nosniff`, which spigot
# sets itself: Shiny's httpResponse() adds it only from 1.14.0.
api_response <- function(status, content_type, content, headers = list()) {
  headers <- as.list(headers)
  if (!any(tolower(names(headers)) == "x-content-type-options")) {
    headers$`X-Content-Type-Options` <- "nosniff"
  }
  shiny::httpResponse(as.integer(status), content_type, content, headers)
}

# A JSON error response: {"error": message}.
json_error <- function(status, message, hint = NULL) {
  api_response(
    status,
    "application/json",
    as.character(spigot_json(c(list(error = message), if (!is.null(hint)) list(hint = hint))))
  )
}
