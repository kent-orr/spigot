doc <- "<html><head><title>{{title}}</title></head><body>{{#items}}<li>{{.}}</li>{{/items}}{{> foot}}</body></html>"

page_html <- function(page, req = fake_req()) as.character(page$render(req))

# ---- spigot_page(): rendering --------------------------------------------------

test_that("spigot_page() renders data and partials into an html_document", {
  p <- spigot_page(doc, data = list(title = "T", items = 1:2),
                   partials = list(foot = "<p>f</p>"))
  expect_s3_class(p, "spigot_page")
  out <- p$render(fake_req())
  expect_s3_class(out, "html_document")
  html <- as.character(out)
  expect_match(html, "<title>T</title>", fixed = TRUE)
  expect_identical(lengths(regmatches(html, gregexpr("<li>", html, fixed = TRUE))), 2L)
  expect_match(html, "<li>1</li><li>2</li><p>f</p>", fixed = TRUE)
})

test_that("Shiny's head content goes just before </head>", {
  p <- spigot_page("<html><head><title>x</title></head><body>b</body></html>")
  expect_match(page_html(p), "<title>x</title><!-- HEAD_CONTENT --></head><body>b</body>",
               fixed = TRUE)
})

test_that("the template and partials can be files; non-ASCII round-trips", {
  dir <- withr::local_tempdir()
  writeLines(enc2utf8("<html><head><title>Größe – ✓</title></head><body>{{> foot}}</body></html>"),
             file.path(dir, "index.html"), useBytes = TRUE)
  writeLines(enc2utf8("<p>{{word}}</p>"), file.path(dir, "foot.html"), useBytes = TRUE)
  p <- spigot_page(file.path(dir, "index.html"), data = list(word = "naïve"),
                   partials = list(foot = file.path(dir, "foot.html")))
  html <- page_html(p)
  expect_identical(Encoding(html), "UTF-8")
  expect_match(html, enc2utf8("<title>Größe – ✓</title>"), fixed = TRUE)
  expect_match(html, enc2utf8("<p>naïve</p>"), fixed = TRUE)

  p <- spigot_page(enc2utf8("<html><head></head><body>{{w}} ✓</body></html>"),
                   data = list(w = "Größe"))
  expect_match(page_html(p), enc2utf8("Größe ✓"), fixed = TRUE)
})

test_that("relative template paths are read from the working directory at creation", {
  dir <- withr::local_tempdir()
  writeLines("<html><head></head><body>from file</body></html>", file.path(dir, "p.html"))
  p <- withr::with_dir(dir, spigot_page("p.html"))
  expect_match(page_html(p), "from file", fixed = TRUE)
})

test_that("data is never evaluated as R, whatever the braces", {
  p <- spigot_page("<html><head><title>{{title}}</title></head><body>{{{raw}}}</body></html>",
                   data = list(title = "{{ Sys.getenv('HOME') }}",
                               raw = "{{ Sys.getenv('HOME') }}"))
  html <- page_html(p)
  expect_match(html, "<title>{{ Sys.getenv('HOME') }}</title>", fixed = TRUE)
  expect_match(html, "<body>{{ Sys.getenv('HOME') }}</body>", fixed = TRUE)
  expect_no_match(html, Sys.getenv("HOME"), fixed = TRUE)
})

test_that("whisker escapes HTML in {{ }} and not in {{{ }}}", {
  p <- spigot_page("<html><head></head><body>{{x}}|{{{x}}}</body></html>",
                   data = list(x = "<b>&</b>"))
  expect_match(page_html(p), "&lt;b&gt;&amp;&lt;/b&gt;|<b>&</b>", fixed = TRUE)
})

test_that("templates see only `data`, not R variables", {
  secret <- "LEAKED"
  p <- spigot_page("<html><head></head><body>[{{secret}}][{{HOME}}]</body></html>")
  expect_match(page_html(p), "[][]", fixed = TRUE)
})

# ---- spigot_page(): </head> ------------------------------------------------------

test_that("a template without </head> is an error naming the template", {
  expect_error(spigot_page("<html><body>no head</body></html>"),
               "<html><body>no head.*</head>")
  f <- withr::local_tempfile(fileext = ".html")
  writeLines("<html><body>x</body></html>", f)
  expect_error(spigot_page(f), basename(f), fixed = TRUE)
})

test_that("</head> is matched case-insensitively and may come from a partial", {
  p <- spigot_page("<HTML><HEAD><TITLE>u</TITLE></HEAD><BODY>b</BODY></HTML>")
  expect_match(page_html(p), "<TITLE>u</TITLE><!-- HEAD_CONTENT --></head><BODY>b</BODY>",
               fixed = TRUE)
  p <- spigot_page("<html>{{> head}}<body>b</body></html>",
                   partials = list(head = "<head><title>p</title></head>"))
  expect_match(page_html(p), "<title>p</title><!-- HEAD_CONTENT --></head><body>b",
               fixed = TRUE)
})

test_that("a render whose output has no </head> is an error", {
  p <- spigot_page("<html>{{#show}}<head></head>{{/show}}<body>b</body></html>",
                   data = function(req) list(show = FALSE))
  expect_error(p$render(fake_req()), "</head>")
})

# ---- spigot_page(): data and cache ------------------------------------------------

test_that("data can be a function of the request, evaluated per request", {
  p <- spigot_page("<html><head></head><body>q={{q}}</body></html>",
                   data = function(req) list(q = req$QUERY_STRING))
  expect_match(page_html(p, fake_req(query = "a=1")), "q=?a=1", fixed = TRUE)
  expect_match(page_html(p, fake_req(query = "b=2")), "q=?b=2", fixed = TRUE)

  p <- spigot_page("<html><head></head><body>{{n}}</body></html>",
                   data = function() list(n = 42))
  expect_match(page_html(p), "<body>42</body>", fixed = TRUE)
})

test_that("a data function must return a list", {
  p <- spigot_page("<html><head></head><body></body></html>", data = function(req) "x")
  expect_error(p$render(fake_req()), "list")
})

test_that("cache = TRUE renders once; cache = FALSE renders every request", {
  calls <- 0L
  real <- render_whisker
  local_mocked_bindings(render_whisker = function(...) {
    calls <<- calls + 1L
    real(...)
  })
  p <- spigot_page("<html><head></head><body>{{x}}</body></html>", data = list(x = 1),
                   cache = TRUE)
  a <- p$render(fake_req())
  b <- p$render(fake_req())
  expect_identical(calls, 1L)
  expect_identical(a, b)

  p <- spigot_page("<html><head></head><body>{{x}}</body></html>", data = list(x = 1))
  p$render(fake_req())
  p$render(fake_req())
  expect_identical(calls, 3L)
})

test_that("cache = TRUE requires static data", {
  expect_error(spigot_page("<html><head></head></html>", data = function(req) list(),
                           cache = TRUE),
               "cache requires static data")
})

# ---- spigot_page(): partials and validation ----------------------------------------

test_that("a partial the template uses but nobody supplied is an error at creation", {
  expect_error(spigot_page("<html><head></head><body>{{> nav}}</body></html>"),
               "nav")
  expect_error(spigot_page("<html><head></head><body>{{>a}}</body></html>",
                           partials = list(a = "{{> b}}")),
               "\"b\"")
})

test_that("a missing partial at render is an error, not a file lookup", {
  # Delimiter changes hide the partial from the creation-time scan.
  p <- spigot_page("<html><head></head><body>{{=<% %>=}}<%> nav%></body></html>")
  withr::local_dir(withr::local_tempdir())
  writeLines("<p>from disk</p>", "nav.mustache")
  expect_error(p$render(fake_req()), "nav")
})

test_that("spigot_page() validates its arguments", {
  expect_error(spigot_page(1), "template")
  expect_error(spigot_page(c("<a>", "<b>")), "template")
  expect_error(spigot_page(NA_character_), "template")
  expect_error(spigot_page("no-such-file.html"), "no-such-file.html")
  ok <- "<html><head></head><body></body></html>"
  expect_error(spigot_page(ok, data = "x"), "data")
  expect_error(spigot_page(ok, data = list(1, 2)), "data")
  expect_error(spigot_page(ok, partials = list("<p>")), "partials")
  expect_error(spigot_page(ok, partials = list(a = 1)), "partials")
  expect_error(spigot_page(ok, cache = NA), "cache")
})

test_that("spigot_page() prints a summary", {
  p <- spigot_page("<html><head></head><body></body></html>", cache = TRUE)
  expect_output(print(p), "spigot_page")
  expect_output(print(p), "cache")
})

# ---- page_router() ----------------------------------------------------------------

two_pages <- function() {
  list(
    "/" = spigot_page("<html><head><title>home</title></head><body></body></html>"),
    "/about" = spigot_page("<html><head><title>about</title></head><body></body></html>")
  )
}

test_that("page_router() serves each page at its path", {
  route <- page_router(two_pages())
  expect_match(as.character(route(fake_req("GET", "/"))), "<title>home</title>", fixed = TRUE)
  expect_match(as.character(route(fake_req("GET", "/about"))), "<title>about</title>",
               fixed = TRUE)
})

test_that("a trailing slash redirects to the page, relative and with the query", {
  route <- page_router(two_pages())
  r <- route(fake_req("GET", "/about/", query = "x=1&y=2"))
  expect_s3_class(r, "httpResponse")
  expect_identical(r$status, 301L)
  expect_identical(r$headers$Location, "../about?x=1&y=2")
  r <- route(fake_req("GET", "/about/"))
  expect_identical(r$headers$Location, "../about")
})

test_that("unknown paths get the spigot 404 page", {
  route <- page_router(two_pages())
  for (path in c("/missing", "/missing/", "/about/x", "/a/b/c", "//")) {
    r <- route(fake_req("GET", path))
    expect_s3_class(r, "httpResponse")
    expect_identical(r$status, 404L, info = path)
    expect_match(r$content_type, "^text/html")
    expect_match(r$content, "Not found", fixed = TRUE)
  }
})

test_that("the 404 page does not echo the path", {
  r <- page_router(two_pages())(fake_req("GET", "/<script>alert(1)</script>"))
  expect_no_match(r$content, "script", fixed = TRUE)
})

test_that("Shiny's reactlog paths fall through to Shiny", {
  route <- page_router(two_pages())
  expect_null(route(fake_req("GET", "/reactlog")))
  expect_null(route(fake_req("GET", "/reactlog/mark")))
})

test_that("pages can be any Shiny UI, or a function of the request", {
  tag <- shiny::fluidPage("plain shiny")
  route <- page_router(list(
    "/" = tag,
    "/fn" = function(req) shiny::tags$p(req$QUERY_STRING),
    "/noargs" = function() shiny::tags$p("no args"),
    "/resp" = function(req) shiny::httpResponse(418L, content = "teapot")
  ))
  expect_identical(route(fake_req("GET", "/")), tag)
  expect_match(as.character(route(fake_req("GET", "/fn", query = "z=9"))), "?z=9", fixed = TRUE)
  expect_match(as.character(route(fake_req("GET", "/noargs"))), "no args", fixed = TRUE)
  expect_identical(route(fake_req("GET", "/resp"))$status, 418L)
})

# ---- as_pages(): the `pages` argument ------------------------------------------------

test_that("a single page, of any kind, is served at /", {
  p <- spigot_page("<html><head></head><body></body></html>")
  expect_identical(as_pages(p), list("/" = p))
  tag <- shiny::fluidPage("x")
  expect_identical(as_pages(tag), list("/" = tag))
  fn <- function(req) "x"
  expect_identical(as_pages(fn), list("/" = fn))
})

test_that("page paths are validated", {
  p <- spigot_page("<html><head></head><body></body></html>")
  expect_error(as_pages(list(p)), "named")
  expect_error(as_pages(list()), "at least one")
  for (bad in c("about", "/about/", "/docs/intro", "", "/a b", "/session", "/shared")) {
    expect_error(as_pages(stats::setNames(list(p), bad)), "path", info = bad)
  }
  expect_error(as_pages(list("/a" = p, "/a" = p)), "more than once")
  expect_error(as_pages(list("/" = NULL)), "page")
  expect_identical(names(as_pages(list("/" = p, "/x.y-z_~" = p))), c("/", "/x.y-z_~"))
})

# ---- integration ---------------------------------------------------------------------

# Number of <script src="..."> tags whose src contains `file`.
scripts <- function(x, file) {
  lengths(regmatches(x, gregexpr(paste0("<script src=\"[^\"]*", file, "[^\"]*\""), x)))
}

test_that("pages are served by a live app, each with Shiny and spigot.js exactly once", {
  srv <- start_app(test_path("apps", "page"))
  r <- hit(paste0(srv$url, "/"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(httr2::resp_content_type(r), "text/html")
  html <- hit_text(r)
  expect_match(html, "<title>home: Größe</title>", fixed = TRUE)
  head <- sub("</head>.*$", "", html)
  expect_identical(scripts(head, "shiny.min.js"), 1L)
  expect_identical(scripts(head, "jquery"), 1L)
  expect_identical(scripts(head, "spigot.js"), 1L)
  expect_identical(scripts(html, "spigot.js"), 1L)
  expect_match(html, "<nav>home | about</nav>", fixed = TRUE)

  r <- hit(paste0(srv$url, "/about"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(hit_text(r), "<title>about</title>", fixed = TRUE)
  expect_identical(scripts(hit_text(r), "spigot.js"), 1L)
})

test_that("a live app redirects a trailing slash and 404s unknown paths", {
  srv <- start_app(test_path("apps", "page"))
  r <- httr2::request(paste0(srv$url, "/about/?q=1")) |>
    httr2::req_options(followlocation = FALSE) |>
    httr2::req_error(is_error = function(r) FALSE) |>
    httr2::req_perform()
  expect_identical(httr2::resp_status(r), 301L)
  expect_identical(httr2::resp_header(r, "Location"), "../about?q=1")
  r <- hit(paste0(srv$url, "/about/"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(hit_text(r), "<title>about</title>", fixed = TRUE)

  r <- hit(paste0(srv$url, "/missing"))
  expect_identical(httr2::resp_status(r), 404L)
  expect_match(httr2::resp_content_type(r), "text/html")
  expect_match(hit_text(r), "Not found", fixed = TRUE)

  # Only GET reaches a page. (Here httpuv answers 400 itself: the app has a
  # www/ folder, and httpuv refuses non-GET requests under a static path.)
  r <- hit(paste0(srv$url, "/about"), "POST", json = list(a = 1))
  expect_gte(httr2::resp_status(r), 400L)
  expect_lt(httr2::resp_status(r), 500L)
  expect_no_match(hit_text(r), "<title>about</title>", fixed = TRUE)
})

test_that("a live app still serves its API, www/ files, Shiny UI pages and data functions", {
  srv <- start_app(test_path("apps", "page"))
  sess <- open_session(srv$url)
  r <- hit(paste0(srv$url, "/api/hello"), headers = list(`X-Spigot-Session` = sess$token))
  expect_identical(httr2::resp_status(r), 200L)
  expect_identical(httr2::resp_body_json(r), list(msg = "hi"))

  expect_identical(hit_text(hit(paste0(srv$url, "/hello.txt"))), "static hello\n")

  html <- hit_text(hit(paste0(srv$url, "/fluid")))
  expect_match(html, "spigot-page-fluid", fixed = TRUE)
  expect_identical(scripts(html, "spigot.js"), 1L)

  a <- hit_text(hit(paste0(srv$url, "/fresh?n=1")))
  b <- hit_text(hit(paste0(srv$url, "/fresh?n=2")))
  expect_match(a, "q=?n=1", fixed = TRUE)
  expect_match(b, "q=?n=2", fixed = TRUE)
  t <- function(x) regmatches(x, regexpr("t=[0-9.]+", x))
  expect_false(identical(t(a), t(b)))

  expect_identical(hit_text(hit(paste0(srv$url, "/cached"))),
                   hit_text(hit(paste0(srv$url, "/cached"))))
})

test_that("a single page is served at / by a live app", {
  srv <- start_app(function() {
    spigot::spigot_app(
      pages = spigot::spigot_page("<html><head><title>solo</title></head><body></body></html>"),
      api = spigot::spigot_api()
    )
  })
  expect_match(hit_text(hit(paste0(srv$url, "/"))), "<title>solo</title>", fixed = TRUE)
  expect_identical(httr2::resp_status(hit(paste0(srv$url, "/other"))), 404L)
})

# ---- e2e -------------------------------------------------------------------------------

test_that("every page gets a working session and API in a browser", {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "page"))
  for (path in c("/", "/about", "/fluid")) {
    tab <- new_tab(paste0(srv$url, path))
    expect_identical(js(tab, "spigot.ready.then(t => t === Shiny.shinyapp.config.sessionId)"),
                     TRUE, info = path)
    expect_identical(js(tab, "spigot.get('hello').then(r => r.msg)"), "hi", info = path)
    tab$close()
  }
})

test_that("a trailing slash lands on the page, also under a proxy subpath", {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "page"))
  tab <- new_tab(paste0(srv$url, "/about/?q=1"))
  expect_identical(js(tab, "location.pathname + location.search"), "/about?q=1")
  expect_identical(js(tab, "spigot.get('hello').then(r => r.msg)"), "hi")
  tab$close()

  proxy <- start_proxy(srv$url)
  tab <- new_tab(paste0(proxy$url, "about/"))
  expect_identical(js(tab, "location.pathname"), "/sub/app/about")
  expect_identical(js(tab, "document.title"), "about")
  expect_identical(js(tab, "spigot.get('hello').then(r => r.msg)"), "hi")
})
