# spigot.js, the browser client (PLAN M3), and spigot_dependency().

# ---- unit: the dependency -------------------------------------------------------

test_that("spigot_dependency() points at the bundled spigot.js", {
  dep <- spigot_dependency()
  expect_s3_class(dep, "html_dependency")
  expect_identical(dep$name, "spigot")
  expect_identical(dep$version, as.character(utils::packageVersion("spigot")))
  expect_identical(dep$package, "spigot")
  expect_true(file.exists(file.path(system.file(dep$src$file, package = "spigot"), "spigot.js")))
})

test_that("spigot_dependency() tells the script the API prefix", {
  html <- as.character(htmltools::renderDependencies(list(spigot_dependency("/v1/data")),
                                                     srcType = "file"))
  expect_match(html, 'src="[^"]*spigot.js"[^>]*data-prefix="/v1/data"')
  html <- as.character(htmltools::renderDependencies(list(spigot_dependency()), srcType = "file"))
  expect_match(html, 'data-prefix="/api"', fixed = TRUE)
})

test_that("spigot_dependency() validates the prefix like spigot_app()", {
  expect_error(spigot_dependency("api"), "prefix")
  expect_error(spigot_dependency('/a"><script>'), "prefix")
  expect_error(spigot_dependency("/session"), "prefix")
})

test_that("attach_spigot() adds the dependency to any kind of ui", {
  dep <- spigot_dependency("/x")
  has_dep <- function(x) {
    deps <- htmltools::findDependencies(x)
    any(vapply(deps, function(d) identical(d$name, "spigot"), logical(1)))
  }

  ui <- attach_spigot(shiny::fluidPage("hi"), dep)
  expect_true(is.function(ui))
  expect_true(has_dep(ui(fake_req())))

  doc <- htmltools::htmlTemplate(text_ = "<html><head>{{ headContent() }}</head><body></body></html>",
                                 document_ = TRUE)
  out <- attach_spigot(doc, dep)(fake_req())
  expect_s3_class(out, "html_document")
  expect_true(has_dep(out))

  seen <- NULL
  ui <- attach_spigot(function(req) {
    seen <<- req
    shiny::tags$p("fn")
  }, dep)
  req <- fake_req(path = "/x")
  expect_true(has_dep(ui(req)))
  expect_identical(seen, req)

  ui <- attach_spigot(function() shiny::tags$p("no req"), dep)
  expect_true(has_dep(ui(fake_req())))

  # spigot_app() reassigns its own `ui` argument to the result.
  ui <- shiny::tags$p("reassigned")
  ui <- attach_spigot(ui, dep)
  expect_true(has_dep(ui(fake_req())))

  resp <- shiny::httpResponse(404L, content = "nope")
  expect_identical(attach_spigot(function(req) resp, dep)(fake_req()), resp)
})

# ---- integration: the page Shiny serves ----------------------------------------

test_that("spigot_app() pages load spigot.js once, after Shiny, with the prefix", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "client"))
  page <- hit_text(hit(paste0(srv$url, "/")))
  scripts <- regmatches(page, gregexpr("<script[^>]*src=\"[^\"]+\"[^>]*>", page))[[1]]
  spigot_tag <- grep("spigot.js", scripts, fixed = TRUE)
  expect_length(spigot_tag, 1)
  expect_gt(spigot_tag, grep("shiny", scripts)[1])
  expect_match(scripts[spigot_tag], 'data-prefix="/api"', fixed = TRUE)

  src <- sub('.*src="([^"]+)".*', "\\1", scripts[spigot_tag])
  r <- hit(paste0(srv$url, "/", src))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(hit_text(r), "SpigotError", fixed = TRUE)
})

# ---- e2e: Chrome ----------------------------------------------------------------

# Every fetch() the page makes, as list(url, method, headers, aborted), where
# `aborted` is read when asked for, so it shows whether the request was later
# aborted.
record_fetches <- function(tab) {
  js(tab, "
    window.__fetches = [];
    const orig = window.fetch;
    window.fetch = function(url, init) {
      window.__fetches.push({url: String(url), init: init || {}});
      return orig.apply(this, arguments);
    };
    true")
}

fetches <- function(tab) {
  js(tab, "window.__fetches.map(f => ({
    url: new URL(f.url, document.baseURI).href,
    method: f.init.method,
    headers: Object.fromEntries(new Headers(f.init.headers || {})),
    aborted: !!(f.init.signal && f.init.signal.aborted)
  }))")
}

# Run `call` (a JS expression giving a promise) and report how it settled.
settle <- function(tab, call) {
  js(tab, sprintf("(%s).then(
    v => ({ok: true, value: v}),
    e => ({ok: false, isSpigotError: e instanceof spigot.SpigotError,
           isError: e instanceof Error, name: e.name, status: e.status,
           message: e.message, body: e.body === undefined ? '<undefined>' : e.body}))", call))
}

client_app <- function(env = parent.frame()) {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "client"), env = env)
  list(srv = srv, tab = new_tab(srv$url, env = env))
}

test_that("spigot.ready resolves with the Shiny session token", {
  x <- client_app()
  id <- js(x$tab, "spigot.ready")
  expect_match(id, "^[0-9a-f]{32}$")
  expect_identical(js(x$tab, "spigot.sessionId"), id)
  expect_identical(js(x$tab, "Shiny.shinyapp.config.sessionId"), id)
})

test_that("a call made before the session exists waits for it", {
  x <- client_app()
  early <- js(x$tab, "window.early.result.then(v => ({
    threw: window.early.threw, before: window.early.sessionAtCall === null, value: v}))")
  expect_null(early$threw)
  expect_true(early$before)
  expect_identical(early$value$query, "?early=1")
  expect_identical(early$value$session, js(x$tab, "spigot.sessionId"))
})

test_that("spigot.get() encodes the query: arrays repeat, null/undefined dropped", {
  x <- client_app()
  v <- js(x$tab, 'spigot.get("echo-query", {a: 1, b: "x y", c: [1, 2], d: null, e: undefined,
                                              f: "&=?/", g: true})')
  expect_identical(v$query, "?a=1&b=x%20y&c=1&c=2&f=%26%3D%3F%2F&g=true")
  expect_identical(js(x$tab, 'spigot.get("echo-query").then(v => v.query)'), "")
  expect_identical(js(x$tab, 'spigot.get("echo-query", {}).then(v => v.query)'), "")
  expect_identical(js(x$tab, 'spigot.get("echo-query?z=0", {a: 1}).then(v => v.query)'),
                   "?z=0&a=1")
})

test_that("spigot.post() sends JSON and parses the JSON reply", {
  x <- client_app()
  record_fetches(x$tab)
  v <- js(x$tab, 'spigot.post("echo-json", {k: [1], s: "é", n: null, o: {p: [true]}})')
  expect_identical(v, list(k = list(1L), s = "é", n = NULL, o = list(p = list(TRUE))))
  f <- fetches(x$tab)[[1]]
  expect_identical(f$method, "POST")
  expect_identical(f$headers$`content-type`, "application/json")
  expect_identical(f$headers$accept, "application/json")

  seen <- js(x$tab, 'fetch("api/echo-json", {method: "POST", body: "{}",
    headers: {"X-Spigot-Session": spigot.sessionId}}).then(r => r.headers.get("X-Seen-Content-Type"))')
  expect_identical(seen, "text/plain;charset=UTF-8") # control: raw fetch differs
  v <- js(x$tab, 'spigot.request("POST", "echo-json", {body: [1]})')
  expect_identical(v, list(1L))
})

test_that("spigot.put() and spigot.del() reach their verbs", {
  x <- client_app()
  v <- js(x$tab, 'spigot.put("echo-method", {a: 1})')
  expect_identical(v, list(method = "PUT", query = "", body = '{"a":1}'))
  v <- js(x$tab, 'spigot.del("echo-method", {id: 7})')
  expect_identical(v, list(method = "DELETE", query = "?id=7", body = ""))
})

test_that("strings, numbers and null are JSON too", {
  x <- client_app()
  expect_identical(js(x$tab, 'spigot.put("echo-method", "hi").then(v => v.body)'), '"hi"')
  expect_identical(js(x$tab, 'spigot.put("echo-method", 3).then(v => v.body)'), "3")
  expect_identical(js(x$tab, 'spigot.put("echo-method", null).then(v => v.body)'), "null")
  expect_identical(js(x$tab, 'spigot.put("echo-method").then(v => v.body)'), "")
})

test_that("non-JSON bodies are sent as they are", {
  x <- client_app()
  record_fetches(x$tab)
  v <- js(x$tab, 'spigot.post("echo-json", new Blob(["raw text"], {type: "text/plain"}))')
  expect_identical(v, "raw text") # the reply is labelled JSON but is not; text is returned
  expect_null(fetches(x$tab)[[1]]$headers$`content-type`)
})

test_that("an empty reply resolves to null", {
  x <- client_app()
  expect_identical(js(x$tab, 'spigot.get("no-content").then(v => v === null)'), TRUE)
})

test_that("non-2xx replies reject with SpigotError", {
  x <- client_app()

  e <- settle(x$tab, 'spigot.get("fail", {status: 422})')
  expect_false(e$ok)
  expect_true(e$isSpigotError)
  expect_true(e$isError)
  expect_identical(e$name, "SpigotError")
  expect_identical(e$status, 422L)
  expect_identical(e$message, "failed with 422")
  expect_identical(e$body, list(error = "failed with 422"))

  e <- settle(x$tab, 'spigot.get("fail", {status: 503, json: false})')
  expect_identical(e$status, 503L)
  expect_identical(e$message, "Service Unavailable")
  expect_identical(e$body, "plain failure")

  e <- settle(x$tab, 'spigot.get("does-not-exist")')
  expect_identical(e$status, 404L)
  expect_match(e$message, "404")

})

test_that("a timeout rejects with status 0 and aborts the request", {
  x <- client_app()
  record_fetches(x$tab)
  t0 <- Sys.time()
  e <- settle(x$tab, 'spigot.get("slow", {ms: 3000}, {timeout: 500})')
  expect_lt(as.numeric(Sys.time() - t0, units = "secs"), 2.5)
  expect_true(e$isSpigotError)
  expect_identical(e$status, 0L)
  expect_match(e$message, "timed out after 500 ms")
  expect_true(fetches(x$tab)[[1]]$aborted)

  v <- settle(x$tab, 'spigot.get("slow", {ms: 50}, {timeout: 2000})')
  expect_true(v$ok)
  expect_false(fetches(x$tab)[[2]]$aborted)
})

test_that("a network failure rejects with status 0", {
  x <- client_app()
  js(x$tab, 'spigot.base = "http://127.0.0.1:1/api/"; true')
  e <- settle(x$tab, 'spigot.get("echo-query")')
  expect_true(e$isSpigotError)
  expect_identical(e$status, 0L)
  expect_match(e$message, "network", ignore.case = TRUE)
})

test_that("the session header is always sent and cannot be overridden", {
  x <- client_app()
  record_fetches(x$tab)
  id <- js(x$tab, "spigot.ready")
  v <- js(x$tab, 'spigot.get("echo-query", {}, {headers: {"X-Custom": "c",
    "x-spigot-session": "0000", Accept: "text/plain"}})')
  expect_identical(v$session, id)
  expect_identical(v$custom, "c")
  expect_identical(v$accept, "text/plain")
  js(x$tab, 'spigot.post("echo-json", {}).then(() => spigot.put("echo-method"))')
  for (f in fetches(x$tab)) expect_identical(f$headers$`x-spigot-session`, id)
})

test_that("relative URLs work under a proxy subpath; leading slashes are not absolute", {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "client"))
  proxy <- start_proxy(srv$url)
  tab <- new_tab(proxy$url)
  record_fetches(tab)
  base <- sub("/$", "", proxy$url)

  expect_identical(js(tab, 'spigot.get("echo-query", {a: 1}).then(v => v.query)'), "?a=1")
  expect_identical(js(tab, 'spigot.get("/echo-query", {b: 2}).then(v => v.query)'), "?b=2")
  expect_identical(js(tab, 'spigot.post("echo-json", {p: 1})'), list(p = 1L))
  urls <- vapply(fetches(tab), `[[`, "", "url")
  expect_identical(urls, paste0(base, c("/api/echo-query?a=1", "/api/echo-query?b=2",
                                         "/api/echo-json")))
  expect_identical(js(tab, "spigot.base"), paste0(base, "/api/"))
})
