# ---- unit: fake requests, no server -----------------------------------------

mount <- function(pr = test_router(), fallback = function(req) NULL, ...) {
  spigot_mount_handler(pr, prefix = "/api", fallback = fallback, ...)
}

test_that("GET and POST reach plumber", {
  h <- mount()
  r <- h(fake_req("GET", "/api/items"))
  expect_s3_class(r, "httpResponse")
  expect_identical(r$status, 200L)
  expect_identical(r$content_type, "application/json")
  expect_identical(resp_text(r), "[1,2,3]")

  r <- h(fake_req("POST", "/api/items", body = list(name = "a", n = 2)))
  expect_identical(r$status, 201L)
  expect_identical(resp_json(r), list(name = "a", n = 2L))
})

test_that("PUT and DELETE reach their routes", {
  h <- mount()
  expect_identical(resp_json(h(fake_req("PUT", "/api/items/7"))), list(verb = "PUT", id = "7"))
  expect_identical(resp_json(h(fake_req("DELETE", "/api/items/7"))), list(verb = "DELETE", id = "7"))
})

test_that("/api and /api/ both hit GET /", {
  h <- mount()
  expect_identical(resp_json(h(fake_req("GET", "/api"))), list(root = TRUE))
  expect_identical(resp_json(h(fake_req("GET", "/api/"))), list(root = TRUE))
})

test_that("the prefix moves from PATH_INFO to SCRIPT_NAME", {
  h <- mount()
  req <- fake_req("GET", "/api/path")
  expect_identical(resp_json(h(req)), list(script = "/api", path = "/path"))
})

test_that("non-prefix paths fall through untouched", {
  seen <- character()
  h <- mount(fallback = function(req) {
    seen <<- c(seen, req$PATH_INFO)
    NULL
  })
  for (p in c("/apix/foo", "/", "/other", "/ap")) {
    req <- fake_req("GET", p)
    expect_null(h(req))
    expect_identical(req$PATH_INFO, p)
    expect_identical(req$SCRIPT_NAME, "")
  }
  expect_identical(seen, c("/apix/foo", "/", "/other", "/ap"))
})

test_that("the fallback's return value is passed through", {
  h <- mount(fallback = function(req) "from-fallback")
  expect_identical(h(fake_req("GET", "/")), "from-fallback")
})

test_that("unknown routes give 404 JSON and wrong verbs give 405", {
  h <- mount()
  r <- h(fake_req("GET", "/api/nope"))
  expect_identical(r$status, 404L)
  expect_match(r$content_type, "^application/json")
  expect_type(resp_json(r)$error, "character")

  r <- h(fake_req("POST", "/api/items-only-get"))
  expect_identical(r$status, 405L)
})

test_that("an endpoint error is a JSON 500 from plumber", {
  h <- mount()
  expect_output(r <- h(fake_req("GET", "/api/boom")), "kaboom") # plumber logs it
  expect_identical(r$status, 500L)
  expect_match(r$content_type, "^application/json")
  expect_false(grepl("<html", resp_text(r), ignore.case = TRUE))
})

test_that("a mount-level failure is a JSON 500, not Shiny's HTML page", {
  broken <- list(call = function(req) stop("router exploded"))
  h <- mount(pr = broken)
  req <- fake_req("GET", "/api/x")
  expect_message(r <- h(req), "router exploded")
  expect_s3_class(r, "httpResponse")
  expect_identical(r$status, 500L)
  expect_identical(r$content_type, "application/json")
  expect_identical(resp_json(r), list(error = "internal server error"))
})

test_that("an async mount-level failure is a JSON 500", {
  broken <- list(call = function(req) promises::promise_reject(simpleError("async exploded")))
  h <- mount(pr = broken)
  p <- h(fake_req("GET", "/api/x"))
  expect_true(promises::is.promising(p))
  expect_message(r <- await(p), "async exploded")
  expect_identical(r$status, 500L)
  expect_identical(resp_json(r), list(error = "internal server error"))
})

test_that("async endpoints return a promise of an httpResponse", {
  h <- mount()
  req <- fake_req("GET", "/api/async")
  p <- h(req)
  expect_true(promises::is.promising(p))
  r <- await(p)
  expect_s3_class(r, "httpResponse")
  expect_identical(r$status, 200L)
  expect_identical(resp_json(r), list(a = 1L))
})

test_that("the prefix stays stripped until an async filter has finished routing", {
  pr <- test_router() |>
    plumber::pr_filter("later", function(req, res) {
      promises::then(promises::promise_resolve(TRUE), function(v) plumber::forward())
    })
  h <- mount(pr = pr)
  r <- await(h(fake_req("GET", "/api/path")))
  expect_identical(r$status, 200L)
  expect_identical(resp_json(r), list(script = "/api", path = "/path"))
})

test_that("a guard can short-circuit or let the request through", {
  calls <- 0L
  spy <- list(call = function(req) {
    calls <<- calls + 1L
    list(status = 200L, headers = list(`Content-Type` = "application/json"), body = "{}")
  })
  deny <- mount(pr = spy, guard = function(req) json_error(403L, "no"))
  r <- deny(fake_req("GET", "/api/x"))
  expect_identical(r$status, 403L)
  expect_identical(calls, 0L)

  allow <- mount(pr = spy, guard = function(req) NULL)
  expect_identical(allow(fake_req("GET", "/api/x"))$status, 200L)
  expect_identical(calls, 1L)
})

test_that("bad prefixes are rejected at construction", {
  pr <- test_router()
  for (p in c("api", "/api/", "/", "", "/session", "/session/x", "/shared",
              "/a b", "/a//b", NA_character_)) {
    expect_error(spigot_mount_handler(pr, prefix = p), "prefix", info = p)
  }
  expect_error(spigot_mount_handler(pr, prefix = c("/a", "/b")), "prefix")
  expect_no_error(spigot_mount_handler(pr, prefix = "/v1/api"))
  expect_no_error(spigot_mount_handler(pr, prefix = "/my-api.v2_x"))
})

test_that("regex characters in the prefix are matched literally", {
  h <- spigot_mount_handler(test_router(), prefix = "/a.i", fallback = function(req) NULL)
  expect_null(h(fake_req("GET", "/abi/items")))
  expect_identical(h(fake_req("GET", "/a.i/items"))$status, 200L)
})

test_that("mount_app() puts the API in front of the app's own handler", {
  app <- shiny::shinyApp(ui = shiny::fluidPage("hello"), server = function(input, output) {})
  orig <- app$httpHandler
  app <- mount_app(app, test_router(), prefix = "/api")
  expect_s3_class(app, "shiny.appobj")
  expect_false(identical(app$httpHandler, orig))
  expect_identical(resp_json(app$httpHandler(fake_req("GET", "/api/"))), list(root = TRUE))
})

test_that("mount_app() falls back to the original handler, not to itself", {
  app <- shiny::shinyApp(ui = shiny::fluidPage("hello"), server = function(input, output) {})
  app <- mount_app(app, test_router(), prefix = "/api")
  r <- app$httpHandler(fake_req("GET", "/"))
  expect_s3_class(r, "httpResponse")
  expect_equal(r$status, 200) # Shiny's own response, passed through as is
  expect_match(resp_text(r), "hello")
})

fake_server <- function() {
  calls <- list()
  list(
    setStaticPath = function(..., .list = NULL) calls[[length(calls) + 1L]] <<- .list,
    calls = function() calls
  )
}

test_that("exclude_static_prefix() excludes the prefix from httpuv static serving", {
  srv <- fake_server()
  expect_true(exclude_static_prefix(srv, "/v1/api"))
  calls <- srv$calls()
  expect_length(calls, 1)
  expect_identical(names(calls[[1]]), "/v1/api")
  expect_identical(calls[[1]][[1]], httpuv::excludeStaticPath())
  expect_false(exclude_static_prefix(NULL, "/api"))
})

test_that("mount_app() keeps the app's onStart and then excludes the prefix", {
  started <- FALSE
  app <- shiny::shinyApp(ui = shiny::fluidPage("x"), server = function(input, output) {},
                         onStart = function() started <<- TRUE)
  app <- mount_app(app, test_router(), prefix = "/api")

  srv <- fake_server()
  old <- shiny::getShinyOption("server", default = NULL)
  shiny::shinyOptions(server = srv)
  withr::defer(shiny::shinyOptions(server = old))

  app$onStart()
  expect_true(started)
  expect_length(srv$calls(), 0) # the server does not exist yet during onStart
  later::run_now()
  expect_identical(names(srv$calls()[[1]]), "/api")
})

test_that("mount_app() works when the app has no onStart", {
  app <- shiny::shinyApp(ui = shiny::fluidPage("x"), server = function(input, output) {})
  app$onStart <- NULL
  app <- mount_app(app, test_router(), prefix = "/api")
  expect_no_error(app$onStart())
  later::run_now()
})

# ---- integration: real httpuv ------------------------------------------------

test_that("the mounted API works over real HTTP", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "mount"))
  u <- srv$url

  r <- hit(paste0(u, "/api/items"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_identical(hit_text(r), "[1,2,3]")

  r <- hit(paste0(u, "/api/items"), "POST", json = list(name = "a", n = 2))
  expect_identical(httr2::resp_status(r), 201L)
  expect_identical(httr2::resp_body_json(r), list(name = "a", n = 2L))

  r <- hit(paste0(u, "/api/items/9"), "PUT")
  expect_identical(httr2::resp_body_json(r), list(verb = "PUT", id = "9"))
  r <- hit(paste0(u, "/api/items/9"), "DELETE")
  expect_identical(httr2::resp_body_json(r), list(verb = "DELETE", id = "9"))

  expect_identical(httr2::resp_status(hit(paste0(u, "/api"))), 200L)
  expect_identical(httr2::resp_status(hit(paste0(u, "/api/nope"))), 404L)
  expect_identical(httr2::resp_status(hit(paste0(u, "/api/items-only-get"), "POST")), 405L)

  r <- hit(paste0(u, "/api/boom"))
  expect_identical(httr2::resp_status(r), 500L)
  expect_match(httr2::resp_content_type(r), "application/json")
})

test_that("binary bodies round-trip byte-exact", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "mount"))
  png <- c(as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)),
           as.raw(0:255), as.raw(255:0))
  r <- hit(paste0(srv$url, "/api/echo-raw"), "POST", raw = png, type = "image/png")
  expect_identical(httr2::resp_status(r), 200L)
  expect_identical(httr2::resp_content_type(r), "application/octet-stream")
  expect_identical(httr2::resp_body_raw(r), png)
})

test_that("Shiny still serves the page and www/ static files", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "mount"))
  r <- hit(paste0(srv$url, "/"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(hit_text(r), "spigot-mount-fixture")
  expect_match(hit_text(r), "shiny")

  r <- hit(paste0(srv$url, "/hello.txt"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_identical(trimws(hit_text(r)), "static ok")
})

test_that("a future_promise endpoint does not block other requests", {
  skip_on_cran()
  skip_if_not_installed("future")
  srv <- start_app(test_path("apps", "mount"))
  slow_url <- paste0(srv$url, "/api/slow")
  hit(slow_url) # warm up the future workers so their start-up is not timed

  # The slow request must come from another process: a shared curl pool
  # serialises the two requests (DECISIONS.md, M0 step 2).
  slow <- callr::r_bg(function(url) {
    t0 <- Sys.time()
    r <- curl::curl_fetch_memory(url)
    list(status = r$status_code, body = rawToChar(r$content),
         secs = as.numeric(Sys.time() - t0, units = "secs"))
  }, args = list(url = slow_url))
  withr::defer(slow$kill())
  Sys.sleep(0.4)

  t0 <- Sys.time()
  fast <- hit(paste0(srv$url, "/api/"))
  fast_secs <- as.numeric(Sys.time() - t0, units = "secs")
  slow$wait(10000)
  s <- slow$get_result()

  expect_identical(httr2::resp_status(fast), 200L)
  expect_lt(fast_secs, 0.5)
  expect_identical(s$status, 200L)
  expect_identical(jsonlite::fromJSON(s$body), list(ok = TRUE))
  expect_gte(s$secs, 1.5)
})
