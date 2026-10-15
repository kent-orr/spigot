# Spike 4: whisker full-document template -> html_document -> Shiny injects deps; no R eval of data.
source("_harness.R")
chrome_setup()

app_fn <- function(port) {
  library(shiny)
  tpl <- '<!DOCTYPE html>
<html lang="en">
<HEAD>
  <meta charset="utf-8">
  <title>{{title}}</title>
</HEAD>
<body>
  <h1 id="title">{{title}}</h1>
  <p id="raw">{{{raw}}}</p>
  <ul>{{#items}}<li>{{.}}</li>{{/items}}</ul>
  {{> footer}}
  <p id="nonascii">{{na}}</p>
</body>
</html>'
  render <- function(data, partials) {
    out <- whisker::whisker.render(tpl, data = data, partials = partials)
    m <- regexpr("</head>", out, ignore.case = TRUE)
    stopifnot(m > 0)
    head_part <- substr(out, 1, m - 1)
    rest_part <- substr(out, m + attr(m, "match.length"), nchar(out))
    htmltools::htmlTemplate(
      text_ = "{{ head }}{{ headContent() }}</head>{{ rest }}",
      head = HTML(head_part), rest = HTML(rest_part), document_ = TRUE
    )
  }
  ui <- function(req) {
    render(list(title = "{{ Sys.getenv('HOME') }}",
                raw = "{{ Sys.getenv('HOME') }}",   # triple-stache: unescaped, still not evaluated
                items = list("a", "b"), na = "Größe – ✓"),
           list(footer = '<footer id="foot">f</footer>'))
  }
  shinyApp(ui = ui, server = function(input, output, session) {})
}

srv <- start_bg(app_fn)
on.exit(srv$proc$kill(), add = TRUE)
html <- body_text(hit(srv$url))
cat(html, "\n")

b <- chromote::ChromoteSession$new()
b$Page$navigate(srv$url); b$Page$loadEventFired(timeout_ = 10)
for (i in 1:100) { if (isTRUE(js(b, "!!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.config)"))) break; Sys.sleep(0.05) }
n_shiny  <- js(b, "document.querySelectorAll('script[src*=\"shiny\"]').length")
n_jquery <- js(b, "document.querySelectorAll('script[src*=\"jquery\"]').length")
check(sprintf("exactly one shiny script (got %d)", n_shiny), n_shiny == 1)
check(sprintf("exactly one jQuery script (got %d)", n_jquery), n_jquery == 1)
check("Shiny.shinyapp defined + connected", isTRUE(js(b, "!!Shiny.shinyapp.config.sessionId")))
check("deps are inside <head>", isTRUE(js(b, "!!document.head.querySelector('script[src*=\"shiny\"]')")))
title <- js(b, "document.title"); h1 <- js(b, "document.getElementById('title').textContent")
raw <- js(b, "document.getElementById('raw').textContent")
cat("  title:", title, "| h1:", h1, "| raw:", raw, "\n")
check("data {{ }} rendered literally, not evaluated", title == "{{ Sys.getenv('HOME') }}" && h1 == title && raw == title)
check("HOME not leaked anywhere", !grepl(Sys.getenv("HOME"), html, fixed = TRUE))
check("items + partial rendered", js(b, "document.querySelectorAll('li').length") == 2 && isTRUE(js(b, "!!document.getElementById('foot')")))
check("non-ASCII round-trips", js(b, "document.getElementById('nonascii').textContent") == "Größe – ✓")
check("uppercase </HEAD> split works, lang attr kept", isTRUE(js(b, "document.documentElement.lang === 'en'")))
check("single <head> / <body>", js(b, "document.querySelectorAll('head').length") == 1 && js(b, "document.querySelectorAll('body').length") == 1)
b$close()

# Negative control: option B (whisker output re-parsed by htmlTemplate) evaluates user data as R.
out_b <- whisker::whisker.render("<html><head></head><body>{{t}}</body></html>",
                                 list(t = "{{ Sys.getenv('HOME') }}"))
b_html <- as.character(htmltools::htmlTemplate(text_ = out_b))
check("option B DOES evaluate data (confirms rejection)", grepl(Sys.getenv("HOME"), b_html, fixed = TRUE))
