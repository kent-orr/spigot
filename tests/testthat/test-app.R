test_that("spigot_app() returns a shiny.appobj with the API mounted", {
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router(), require_session = FALSE)
  expect_s3_class(app, "shiny.appobj")
  r <- app$httpHandler(fake_req("GET", "/api/items"))
  expect_identical(r$status, 200L)
  expect_identical(resp_text(r), "[1,2,3]")
})

test_that("spigot_app() honours a custom prefix", {
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router(), prefix = "/rpc",
                    require_session = FALSE)
  expect_identical(app$httpHandler(fake_req("GET", "/rpc/items"))$status, 200L)
})

test_that("spigot_app() accepts a plumber file and applies spigot_json()", {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(c("#* @get /hi", "function() list(ok = TRUE)"), f)
  app <- spigot_app(pages = shiny::fluidPage("x"), api = f, require_session = FALSE)
  expect_identical(resp_text(app$httpHandler(fake_req("GET", "/api/hi"))), '{"ok":true}')
})

test_that("spigot_app() serves a Plumber router as given", {
  pr <- plumber::pr() |> plumber::pr_get("/b", function() list(x = 1))
  app <- spigot_app(pages = shiny::fluidPage("x"), api = pr, require_session = FALSE)
  expect_identical(resp_text(app$httpHandler(fake_req("GET", "/api/b"))), '{"x":[1]}')
})

test_that("spigot_app() requires a live session by default", {
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router())
  r <- app$httpHandler(fake_req("GET", "/api/items"))
  expect_identical(r$status, 401L)
  expect_identical(resp_json(r)$error, "session required")
  expect_identical(resp_json(r)$hint, SESSION_HINT)

  s <- local_session()
  r <- app$httpHandler(fake_req("GET", "/api/items", headers = session_header(s)))
  expect_identical(r$status, 200L)
})

test_that("spigot_app() refuses cross-origin API calls", {
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router(), require_session = FALSE)
  r <- app$httpHandler(fake_req("POST", "/api/items", body = list(a = 1),
                                headers = list(Origin = "http://evil.test")))
  expect_identical(r$status, 403L)
})

test_that("spigot_app() registers each session before the user's server runs", {
  seen <- NULL
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router(),
                    server = function(input, output, session) {
                      seen <<- identical(lookup_session(session$token), session)
                    })
  server <- app$serverFuncSource()
  s <- fake_session()
  withr::defer(s$end())
  do.call(server, shiny:::argsForServerFunc(server, s))
  expect_true(seen)
})

test_that("spigot_app() registers sessions when there is no server", {
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router())
  server <- app$serverFuncSource()
  s <- fake_session()
  withr::defer(s$end())
  do.call(server, shiny:::argsForServerFunc(server, s))
  expect_identical(lookup_session(s$token), s)
})

test_that("max_request_size sets shiny.maxRequestSize while the app runs", {
  withr::local_options(shiny.maxRequestSize = 123)
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router(), max_request_size = 2048)
  during <- NULL
  later::later(function() {
    during <<- getOption("shiny.maxRequestSize")
    shiny::stopApp()
  }, 0.2)
  shiny::runApp(app, port = httpuv::randomPort(), launch.browser = FALSE, quiet = TRUE)
  expect_identical(during, 2048)
  expect_identical(getOption("shiny.maxRequestSize"), 123)
})

test_that("max_request_size = NULL leaves shiny.maxRequestSize alone", {
  withr::local_options(shiny.maxRequestSize = 123)
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router())
  app$onStart()
  expect_identical(getOption("shiny.maxRequestSize"), 123)
})

test_that("spigot_app() validates its arguments", {
  ui <- shiny::fluidPage("x")
  expect_error(spigot_app(pages = ui), "api")
  expect_error(spigot_app(pages = ui, api = test_router(), prefix = "api"), "prefix")
  expect_error(spigot_app(pages = ui, api = test_router(), require_session = NA), "require_session")
  expect_error(spigot_app(pages = ui, api = test_router(), server = "x"), "server")
  for (bad in list("1", NA_real_, c(1, 2), -1)) {
    expect_error(spigot_app(pages = ui, api = test_router(), max_request_size = bad),
                 "max_request_size")
  }
})

test_that("spigot_app() requires pages", {
  expect_error(spigot_app(api = test_router()), "pages")
})

test_that("spigot_app() serves its pages through Shiny, with spigot.js", {
  app <- spigot_app(
    pages = list(
      "/" = spigot_page("<html><head><title>home</title></head><body></body></html>"),
      "/about" = shiny::fluidPage("about-page")
    ),
    api = test_router()
  )
  r <- app$httpHandler(fake_req("GET", "/"))
  expect_equal(r$status, 200)
  expect_match(r$content, "<title>home</title>", fixed = TRUE)
  expect_match(r$content, "spigot.js", fixed = TRUE)
  expect_match(app$httpHandler(fake_req("GET", "/about"))$content, "about-page", fixed = TRUE)
  expect_identical(app$httpHandler(fake_req("GET", "/about/"))$status, 301L)
  expect_identical(app$httpHandler(fake_req("GET", "/nope"))$status, 404L)
  # The API is mounted in front of the pages.
  expect_identical(app$httpHandler(fake_req("GET", "/api/items"))$status, 401L)
})

test_that("spigot_app() refuses a page the API would hide", {
  p <- spigot_page("<html><head></head><body></body></html>")
  expect_error(spigot_app(pages = list("/" = p, "/api" = p), api = test_router()),
               "/api")
  expect_error(spigot_app(pages = list("/rpc" = p), api = test_router(), prefix = "/rpc"),
               "/rpc")
  # A page that only shares the prefix's first characters is fine.
  expect_s3_class(spigot_app(pages = list("/apis" = p), api = test_router()), "shiny.appobj")
})
