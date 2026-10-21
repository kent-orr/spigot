# Blueprints: spigot_blueprint() and spigot_app(blueprints =). The fixture
# apps/blueprint/ has one blueprint, `cars`, defined in its R/cars.R.

doc <- function(body = "") {
  spigot_page(paste0("<html><head></head><body>", body, "</body></html>"))
}

# ---- spigot_blueprint() ---------------------------------------------------------------

test_that("spigot_blueprint() records its pages, API, templates, partials and static", {
  bp <- spigot_blueprint(pages = list("/" = doc("list"), "/model" = doc("model")),
                         api = "api/cars.R", templates = "templates/cars",
                         partials = "templates/cars/partials", static = "static/cars")
  expect_s3_class(bp, "spigot_blueprint")
  expect_named(bp$pages, c("/", "/model"))
  expect_identical(bp$api, "api/cars.R")
  expect_identical(bp$templates, "templates/cars")
  expect_identical(bp$partials, "templates/cars/partials")
  expect_identical(bp$static, "static/cars")

  router <- spigot_api() |> plumber::pr_get("/fit", function() list(ok = TRUE))
  expect_identical(spigot_blueprint(doc(), api = router)$api, router)
  bp <- spigot_blueprint(doc())
  expect_named(bp$pages, "/")
  expect_null(bp$api)
})

test_that("spigot_blueprint() validates its arguments", {
  expect_error(spigot_blueprint(list("model" = doc())), "Page path \"model\"")
  expect_error(spigot_blueprint(list("/model/" = doc())), "Page path \"/model/\"")
  expect_error(spigot_blueprint(list(doc())), "named by path")
  expect_error(spigot_blueprint(doc(), api = 1), "`api` must be")
  expect_error(spigot_blueprint(doc(), templates = 1), "`templates` must be")
  expect_error(spigot_blueprint(doc(), partials = 1), "`partials` must be")
  expect_error(spigot_blueprint(doc(), static = list(a = "x")), "`static` must be")
})

test_that("spigot_blueprint() prints its pages and whether it has an API", {
  bp <- spigot_blueprint(list("/" = doc(), "/model" = doc()), api = "api/cars.R")
  expect_output(print(bp), "spigot_blueprint")
  expect_output(print(bp), "pages: +/, /model")
  expect_output(print(bp), "api: +api/cars.R")
  expect_output(print(spigot_blueprint(doc())), "api: +none")
})

# ---- register_blueprints() ------------------------------------------------------------

test_that("register_blueprints() puts each blueprint's pages under its prefix", {
  bp <- spigot_blueprint(list("/" = doc("list"), "/model" = doc("model")))
  pages <- register_blueprints(list("/" = doc("home")), list("/cars" = bp), "/api")
  expect_named(pages, c("/", "/cars", "/cars/model"))
  expect_identical(pages[["/cars"]]$blueprint, "/cars")
  expect_null(pages[["/"]]$blueprint)

  pages <- register_blueprints(list("/" = doc()), list("/a/b" = bp), "/api")
  expect_named(pages, c("/", "/a/b", "/a/b/model"))
  expect_identical(register_blueprints(list("/" = doc()), NULL, "/api"), list("/" = doc()))
})

test_that("a page path claimed twice is an error naming both owners", {
  bp <- spigot_blueprint(list("/" = doc(), "/x" = doc()))
  expect_error(register_blueprints(list("/cars" = doc()), list("/cars" = bp), "/api"),
               "\"/cars\".*blueprint \"/cars\".*app")
  expect_error(register_blueprints(list("/" = doc()),
                                   list("/cars" = bp, "/cars/x" = bp), "/api"),
               "\"/cars/x\" of the blueprint \"/cars/x\" is also a page of the blueprint \"/cars\"")
})

test_that("blueprint prefixes are page paths other than /, not under the API", {
  bp <- spigot_blueprint(doc())
  expect_error(register_blueprints(list(), list("/" = bp), "/api"), "blueprint prefix \"/\"")
  expect_error(register_blueprints(list(), list("cars" = bp), "/api"), "blueprint prefix \"cars\"")
  expect_error(register_blueprints(list(), list("/api/cars" = bp), "/api"), "API prefix")
  expect_error(register_blueprints(list(), list(bp), "/api"), "named by prefix")
  expect_error(register_blueprints(list(), list("/cars" = doc()), "/api"), "spigot_blueprint")
  expect_error(register_blueprints(list(), list("/cars" = bp, "/cars" = bp), "/api"),
               "more than once")
})

test_that("a blueprint page's data gains `static` when the blueprint has static files", {
  page_data <- function(bp, prefix = "/cars") {
    register_blueprints(list(), stats::setNames(list(bp), prefix), "/api")[[prefix]]$data
  }
  expect_identical(page_data(spigot_blueprint(doc(), static = "s")), list(static = "cars/static"))
  expect_identical(page_data(spigot_blueprint(doc(), static = "s"), "/a/b"),
                   list(static = "a/b/static"))
  expect_identical(page_data(spigot_blueprint(doc())), list())

  # A user's own `static` wins.
  p <- spigot_page("<html><head></head></html>", data = list(static = "mine", x = 1))
  expect_identical(page_data(spigot_blueprint(p, static = "s")), list(static = "mine", x = 1))

  # A data function gets it added to its result, the user's key still winning.
  p <- spigot_page("<html><head></head></html>", data = function(req) list(q = req$QUERY_STRING))
  f <- page_data(spigot_blueprint(p, static = "s"))
  expect_identical(f(fake_req(query = "a=1")), list(q = "?a=1", static = "cars/static"))
  p <- spigot_page("<html><head></head></html>", data = function() list(static = "mine"))
  expect_identical(page_data(spigot_blueprint(p, static = "s"))(fake_req()), list(static = "mine"))
})

# ---- spigot_app(blueprints =), in process -----------------------------------------------

app_get <- function(app, path) app$httpHandler(fake_req("GET", path))

test_that("an app serves its blueprints' pages and mounts their APIs under its prefix", {
  root <- local_tree(c(
    "templates/page.html" = "<html><head></head><body>app {{> nav}}</body></html>",
    "templates/partials/nav.html" = "<nav>app nav</nav>",
    "bp/templates/page.html" = "<html><head></head><body>bp {{> nav}} {{static}}</body></html>",
    "bp/partials/nav.html" = "<nav>bp nav</nav>",
    "bp/static/x.js" = "x"
  ))
  cars <- spigot_blueprint(
    pages = list("/" = spigot_page("page.html"), "/other" = spigot_page("page.html")),
    api = spigot_api() |> plumber::pr_get("/fit", function() list(fit = "ok")),
    templates = "bp/templates", partials = "bp/partials", static = "bp/static"
  )
  app <- spigot_app(pages = list("/" = spigot_page("page.html")), api = test_router(),
                    blueprints = list("/cars" = cars), templates = "templates",
                    partials = "templates/partials", root = root, require_session = FALSE)

  expect_match(resp_text(app_get(app, "/")), "app <nav>app nav</nav>", fixed = TRUE)
  for (path in c("/cars", "/cars/other")) {
    expect_match(resp_text(app_get(app, path)), "bp <nav>bp nav</nav> cars/static",
                 fixed = TRUE, info = path)
  }
  r <- app_get(app, "/api/cars/fit")
  expect_identical(r$status, 200L)
  expect_identical(jsonlite::fromJSON(resp_text(r)), list(fit = "ok"))
  expect_identical(app_get(app, "/api/items")$status, 200L) # the app's own API still works

  paths <- start_with_server(app, fake_server())$calls()[[1]]
  expect_identical(paths[["/cars/static"]], httpuv::staticPath(file.path(root, "bp", "static")))
})

test_that("a blueprint's API file is read relative to root, in the blueprint's environment", {
  root <- local_tree(list("api/cars.R" = c("#* @get /fit", "function() list(fit = helper())")))
  helper <- function() "from the blueprint's environment"
  cars <- spigot_blueprint(doc(), api = "api/cars.R")
  app <- spigot_app(pages = doc(), api = test_router(), blueprints = list("/cars" = cars),
                    root = root, require_session = FALSE)
  r <- app_get(app, "/api/cars/fit")
  expect_identical(jsonlite::fromJSON(resp_text(r))$fit, "from the blueprint's environment")
})

test_that("spigot_app() runs every page check on the blueprints' pages", {
  root <- local_tree(c("s/x.js" = "x"))
  nested_ui <- spigot_blueprint(list("/" = doc(), "/deep" = shiny::fluidPage("x")))
  expect_error(spigot_app(pages = doc(), api = test_router(),
                          blueprints = list("/cars" = nested_ui)),
               "\"/cars/deep\" must be a spigot_page")
  under_static <- spigot_blueprint(doc())
  expect_error(spigot_app(pages = doc(), api = test_router(), static = list(cars = "s"),
                          blueprints = list("/cars" = under_static), root = root),
               "\"/cars\" is under the static path \"/cars\"")
  missing <- spigot_blueprint(spigot_page("nope.html"))
  expect_error(spigot_app(pages = doc(), api = test_router(),
                          blueprints = list("/cars" = missing), root = root),
               "Can't find the template file \"nope.html\"")
})

# ---- a live app ----------------------------------------------------------------------

test_that("a live app serves a blueprint's pages, static files and guarded API", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "blueprint"))
  sess <- open_session(srv$url)
  token <- list(`X-Spigot-Session` = sess$token)

  r <- hit(paste0(srv$url, "/cars"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(hit_text(r), "<nav>cars nav</nav> 32 cars", fixed = TRUE)
  expect_match(hit_text(r), "<script src=\"cars/static/cars.js\">", fixed = TRUE)
  expect_match(hit_text(hit(paste0(srv$url, "/cars/model"))), "<nav>cars nav</nav> model",
               fixed = TRUE)

  r <- hit(paste0(srv$url, "/cars/static/cars.js"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(httr2::resp_content_type(r), "javascript")

  expect_identical(httr2::resp_status(hit(paste0(srv$url, "/api/cars/fit"))), 401L)
  r <- hit(paste0(srv$url, "/api/cars/fit"), headers = token)
  expect_identical(httr2::resp_status(r), 200L)
  expect_identical(httr2::resp_body_json(r), list(fit = "ok", session = TRUE))
  expect_identical(httr2::resp_status(hit(paste0(srv$url, "/api/ping"), headers = token)), 200L)

  # The blueprint's templates and partials shadow the app's, only for its pages.
  expect_match(hit_text(hit(paste0(srv$url, "/common"))), "app common <nav>app nav</nav>",
               fixed = TRUE)
  expect_match(hit_text(hit(paste0(srv$url, "/cars/common"))), "cars common <nav>cars nav</nav>",
               fixed = TRUE)
})

test_that("in a browser, a nested blueprint page loads its static file and calls its API", {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "blueprint"))
  tab <- new_tab(paste0(srv$url, "/cars/model"))
  expect_true(js(tab, "window.carsLoaded === true"))
  expect_identical(js(tab, "spigot.get('cars/fit').then(r => r.fit)"), "ok")
})
