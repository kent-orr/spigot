# Spike 3: Shiny.shinyapp.config.sessionId === session$token; time until it exists.
source("_harness.R")
chrome_setup()
token_file <- tempfile(fileext = ".txt")

app_fn <- local({
  tf <- token_file
  function(port) {
    library(shiny)
    probe <- tags$script(HTML("
      window.__t = {};
      document.addEventListener('DOMContentLoaded', function () {
        var t0 = performance.now(); window.__t.dcl = t0;
        $(document).on('shiny:connected', function () { window.__t.connected = performance.now() - t0; });
        $(document).on('shiny:sessioninitialized', function () {
          window.__t.sessioninit = performance.now() - t0;
          window.__t.id_at_sessioninit = !!(Shiny.shinyapp.config && Shiny.shinyapp.config.sessionId);
        });
        (function poll() {
          if (window.Shiny && Shiny.shinyapp && Shiny.shinyapp.config && Shiny.shinyapp.config.sessionId) {
            window.__t.config = performance.now() - t0;
          } else setTimeout(poll, 1);
        })();
      });"))
    shinyApp(ui = fluidPage(tags$head(probe), "hi"),
             server = function(input, output, session) {
               message("TOKEN ", session$token); writeLines(session$token, tf)
             })
  }
})

srv <- start_bg(app_fn)
on.exit(srv$proc$kill(), add = TRUE)

res <- replicate(5, simplify = FALSE, {
  unlink(token_file)
  b <- chromote::ChromoteSession$new()
  b$Page$navigate(srv$url); b$Page$loadEventFired(timeout_ = 10)
  for (i in 1:100) { if (isTRUE(js(b, "!!(window.__t && window.__t.config && window.__t.connected)"))) break; Sys.sleep(0.05) }
  out <- list(js_token = js(b, "Shiny.shinyapp.config.sessionId"),
              r_token = readLines(token_file),
              config_ms = js(b, "window.__t.config"),
              connected_ms = js(b, "window.__t.connected"),
              sessioninit_ms = js(b, "window.__t.sessioninit"),
              id_at_connected_event = js(b, "''+(window.__t.config <= window.__t.connected)"),
              id_at_sessioninit_event = js(b, "''+window.__t.id_at_sessioninit"),
              has_initializedPromise = js(b, "''+(typeof Shiny.initializedPromise)"))
  b$close(); out
})
df <- do.call(rbind, lapply(res, as.data.frame)); df$js_token <- substr(df$js_token, 1, 8); df$r_token <- substr(df$r_token, 1, 8); print(df)
check("JS sessionId == session$token (all 5)", all(vapply(res, \(x) identical(x$js_token, x$r_token), logical(1))))
check("token is lowercase hex >= 16", all(grepl("^[0-9a-f]{16,}$", vapply(res, `[[`, "", "r_token"))))
check("sessionId NOT yet set at shiny:connected", all(vapply(res, \(x) x$id_at_connected_event == "false", logical(1))))
check("sessionId set at shiny:sessioninitialized", all(vapply(res, \(x) x$id_at_sessioninit_event == "true", logical(1))))
