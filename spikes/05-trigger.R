# Spike 5: round-trip reactive bridge latency (option 1 in PLAN §4.5).
source("_harness.R")
chrome_setup()

app_fn <- function(port) {
  library(shiny)
  reg <- new.env(parent = emptyenv())
  pr <- plumber::pr() |>
    plumber::pr_post("/tick", function(req, i) {
      s <- reg[[req$HTTP_X_SPIGOT_SESSION]]
      s$sendCustomMessage("spigot:set-input", list(name = "tick", value = as.integer(i)))
      list(ok = TRUE)
    })
  conv <- function(res) {
    h <- res$headers; ct_i <- which(tolower(names(h)) == "content-type")
    ct <- if (length(ct_i)) h[[ct_i[1]]] else "application/octet-stream"
    if (length(ct_i)) h <- h[-ct_i]
    shiny::httpResponse(res$status, ct, if (is.null(res$body)) "" else res$body, h)
  }
  js_client <- tags$script(HTML("
    Shiny.addCustomMessageHandler('spigot:set-input', function (m) {
      window.__setinput[m.value] = performance.now();
      Shiny.setInputValue(m.name, m.value, {priority: 'event'});
    });
    window.__pongs = {}; window.__setinput = {};
    Shiny.addCustomMessageHandler('pong', function (i) { window.__pongs[i] = performance.now(); });
    window.runBench = async function (n) {
      var out = [];
      for (var i = 0; i < n; i++) {
        var t0 = performance.now();
        await fetch('api/tick', {method: 'POST', headers: {'Content-Type': 'application/json',
          'X-Spigot-Session': Shiny.shinyapp.config.sessionId}, body: JSON.stringify({i: i})});
        var t1 = performance.now();
        while (!(i in window.__pongs)) await new Promise(r => setTimeout(r, 0));
        out.push({start: t0, resolved: t1, setinput: window.__setinput[i], pong: window.__pongs[i]});
      }
      return out;
    };
    window.runPlain = async function (n, base) {
      var out = [];
      for (var i = base; i < base + n; i++) {
        var t0 = performance.now();
        Shiny.setInputValue('tick', i, {priority: 'event'});
        while (!(i in window.__pongs)) await new Promise(r => setTimeout(r, 0));
        out.push(window.__pongs[i] - t0);
      }
      return out;
    };"))
  app <- shinyApp(
    ui = fluidPage(tags$head(js_client), "bench"),
    server = function(input, output, session) {
      reg[[session$token]] <- session
      observeEvent(input$tick, session$sendCustomMessage("pong", input$tick))
    })
  orig <- app$httpHandler
  app$httpHandler <- function(req) {
    if (!grepl("^/api(/|$)", req$PATH_INFO)) return(orig(req))
    req$SCRIPT_NAME <- paste0(req$SCRIPT_NAME, "/api")
    req$PATH_INFO <- sub("^/api", "", req$PATH_INFO)
    conv(pr$call(req))
  }
  app
}

srv <- start_bg(app_fn)
on.exit(srv$proc$kill(), add = TRUE)
b <- chromote::ChromoteSession$new()
b$Page$navigate(srv$url); b$Page$loadEventFired(timeout_ = 10)
for (i in 1:100) { if (isTRUE(js(b, "!!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.config && Shiny.shinyapp.config.sessionId)"))) break; Sys.sleep(0.05) }
invisible(js(b, "runBench(5)"))            # warm-up
res <- js(b, "runBench(50)", timeout = 60)
d <- do.call(rbind, lapply(res, as.data.frame))
d$resolve_to_pong <- d$pong - d$resolved
d$start_to_pong   <- d$pong - d$start
d$http_rtt        <- d$resolved - d$start
d$start_to_setinput <- d$setinput - d$start
d$setinput_to_pong  <- d$pong - d$setinput
q <- function(x) sprintf("median %.1f ms, p95 %.1f ms, max %.1f ms", median(x), quantile(x, .95), max(x))
cat("  HTTP round-trip      :", q(d$http_rtt), "\n")
cat("  fetch-resolve -> pong:", q(d$resolve_to_pong), "\n")
cat("  fetch-start   -> pong:", q(d$start_to_pong), "\n")
cat("  fetch-start -> set-input msg:", q(d$start_to_setinput), "\n")
cat("  set-input -> pong (ws up, observer, ws down):", q(d$setinput_to_pong), "\n")
cat("  pong before fetch resolved in", sum(d$resolve_to_pong < 0), "of", nrow(d), "\n")
check("p95 fetch-resolve -> pong < 50 ms (adopt option 1)", quantile(d$resolve_to_pong, .95) < 50)
plain <- unlist(js(b, "runPlain(50, 1000)", timeout = 60))
cat("  baseline: plain Shiny setInputValue -> observer -> pong:", q(plain), "\n")
b$close()
