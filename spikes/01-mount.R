# Spike 1: mount reaches all verbs; rook.input pre-read behaviour; PATH_INFO after strip.
source("_harness.R")

app_fn <- function(port) {
  library(shiny)
  pr <- plumber::pr() |>
    plumber::pr_get("/", function() list(root = TRUE)) |>
    plumber::pr_post("/echo", function(req) req$body) |>
    plumber::pr_put("/x", function() list(verb = "PUT")) |>
    plumber::pr_delete("/x", function() list(verb = "DELETE")) |>
    plumber::pr_get("/pathinfo", function(req) list(path = req$PATH_INFO))

  rook_to_httpResponse <- function(res) {
    h <- res$headers
    ct_i <- which(tolower(names(h)) == "content-type")
    ct <- if (length(ct_i)) h[[ct_i[1]]] else "application/octet-stream"
    if (length(ct_i)) h <- h[-ct_i]
    shiny::httpResponse(res$status, ct, if (is.null(res$body)) "" else res$body, h)
  }

  app <- shinyApp(ui = fluidPage("hi"), server = function(input, output, session) {})
  orig <- app$httpHandler
  app$httpHandler <- function(req) {
    path <- req$PATH_INFO
    if (!grepl("^/api(/|$)", path)) return(orig(req))
    old_sn <- req$SCRIPT_NAME; old_pi <- req$PATH_INFO
    on.exit({ req$SCRIPT_NAME <- old_sn; req$PATH_INFO <- old_pi })
    req$SCRIPT_NAME <- paste0(old_sn, "/api")
    req$PATH_INFO <- sub("^/api", "", path)
    stripped <- req$PATH_INFO
    if (!is.null(req$HTTP_X_PREREAD)) {
      req$rook.input$read()
      if (identical(req$HTTP_X_PREREAD, "rewind")) req$rook.input$rewind()
    }
    if (identical(req$PATH_INFO, "")) req$PATH_INFO <- "/"
    out <- rook_to_httpResponse(pr$call(req))
    out$headers[["X-Stripped-Path"]] <- stripped
    out
  }
  app
}

srv <- start_bg(app_fn)
on.exit(srv$proc$kill(), add = TRUE)
u <- srv$url

r <- hit(paste0(u, "/api/")); check("GET /api/ -> 200", httr2::resp_status(r) == 200); print(body_text(r))
r <- hit(paste0(u, "/api")); check("GET /api -> 200 (after ''->'/')", httr2::resp_status(r) == 200)
cat("  PATH_INFO after stripping '/api' exactly: '", httr2::resp_header(r, "X-Stripped-Path"), "'\n", sep = "")
r <- hit(paste0(u, "/api/echo"), "POST", json = list(a = 1, b = list("x", "y")))
check("POST /api/echo -> 200 + echo", httr2::resp_status(r) == 200); print(body_text(r))
r <- hit(paste0(u, "/api/x"), "PUT"); check("PUT /api/x", httr2::resp_status(r) == 200 && grepl("PUT", body_text(r)))
r <- hit(paste0(u, "/api/x"), "DELETE"); check("DELETE /api/x", httr2::resp_status(r) == 200 && grepl("DELETE", body_text(r)))
r <- hit(paste0(u, "/api/x"), "POST"); cat("  POST /api/x (wrong verb) ->", httr2::resp_status(r), "\n")
r <- hit(paste0(u, "/api/pathinfo")); cat("  plumber sees req$PATH_INFO =", body_text(r), "\n")
r <- hit(paste0(u, "/")); check("GET / still served by Shiny", httr2::resp_status(r) == 200 && grepl("shiny", body_text(r)))

r <- hit(paste0(u, "/api/echo"), "POST", json = list(a = 1), headers = list(`X-Preread` = "yes"))
cat("  pre-read, no rewind -> status", httr2::resp_status(r), "body:", body_text(r), "\n")
r <- hit(paste0(u, "/api/echo"), "POST", json = list(a = 1), headers = list(`X-Preread` = "rewind"))
cat("  pre-read + rewind   -> status", httr2::resp_status(r), "body:", body_text(r), "\n")
