# Spike 2: a promise returned from app$httpHandler is awaited, and does not block other requests.
source("_harness.R")

app_fn <- function(port) {
  library(shiny)
  future::plan(future::multisession, workers = 2)
  pr <- plumber::pr() |>
    plumber::pr_get("/", function() list(root = TRUE)) |>
    plumber::pr_get("/slow", function() {
      promises::future_promise({ Sys.sleep(2); list(ok = TRUE) })
    })
  conv <- function(res) {
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
    req$SCRIPT_NAME <- paste0(req$SCRIPT_NAME, "/api")
    req$PATH_INFO <- sub("^/api", "", path)
    if (identical(req$PATH_INFO, "")) req$PATH_INFO <- "/"
    res <- pr$call(req)
    if (promises::is.promising(res)) promises::then(res, conv) else conv(res)
  }
  app
}

srv <- start_bg(app_fn)
on.exit(srv$proc$kill(), add = TRUE)
u <- srv$url
# warm up the future workers so their startup time is not measured
invisible(hit(paste0(u, "/api/slow")))

# Fire /slow from a separate process so client-side connection reuse cannot serialise them.
slow <- callr::r_bg(function(url) {
  t <- Sys.time(); r <- curl::curl_fetch_memory(url)
  list(status = r$status_code, body = rawToChar(r$content), secs = as.numeric(Sys.time() - t, units = "secs"))
}, args = list(url = paste0(u, "/api/slow")))
Sys.sleep(0.5)  # /slow is in flight
t <- Sys.time(); fast <- hit(paste0(u, "/api/")); fast_secs <- as.numeric(Sys.time() - t, units = "secs")
slow$wait(); sres <- slow$get_result()
cat(sprintf("  /slow: %.2f s  status %d  %s\n  /    : %.3f s while /slow in flight\n", sres$secs, sres$status, sres$body, fast_secs))
check("/slow returns 200 {ok:true} via promise", sres$status == 200 && grepl("ok", sres$body))
check("/slow took >= 2 s", sres$secs >= 2)
check("/ returned < 500 ms while /slow pending (process not blocked)", fast_secs < 0.5)
