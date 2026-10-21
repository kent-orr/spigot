# Static dirs (spigot_app(static =, root =)), unit level. Serving them is
# tested in test-launch.R (both launch modes) and test-page.R (nested pages).

# A temporary root holding the named empty dirs; returns its normalized path.
local_root <- function(dirs = character(), env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  for (d in dirs) dir.create(file.path(root, d), recursive = TRUE)
  normalizePath(root)
}

test_that("resolve_root() resolves against the working directory, now", {
  wd <- local_root("sub")
  withr::local_dir(wd)
  expect_identical(resolve_root("."), wd)
  expect_identical(resolve_root("sub"), file.path(wd, "sub"))
  expect_identical(resolve_root(file.path(wd, "sub")), file.path(wd, "sub"))
})

test_that("resolve_root() needs an existing dir", {
  withr::local_dir(local_root())
  expect_error(resolve_root("nope"), "`root`.*\"nope\"")
  writeLines("x", "file.txt")
  expect_error(resolve_root("file.txt"), "`root`")
  for (bad in list(NULL, NA_character_, c(".", "."), 1)) {
    expect_error(resolve_root(bad), "`root` must be")
  }
})

test_that("check_static() serves one dir at /static", {
  root <- local_root("assets")
  expect_identical(check_static("assets", root),
                   list("/static" = file.path(root, "assets")))
})

test_that("check_static() serves a named list of dirs at /<name> each", {
  root <- local_root(c("js", "img/png"))
  expect_identical(check_static(list(scripts = "js", pics = "img/png"), root),
                   list("/scripts" = file.path(root, "js"),
                        "/pics" = file.path(root, "img", "png")))
})

test_that("check_static() takes NULL as no static dirs", {
  expect_identical(check_static(NULL, local_root()), list())
})

test_that("an absolute static dir is not resolved against root", {
  other <- local_root("abs")
  expect_identical(check_static(file.path(other, "abs"), local_root()),
                   list("/static" = file.path(other, "abs")))
})

test_that("check_static() needs one name per dir in a list", {
  root <- local_root(c("a", "b"))
  expect_error(check_static(list("a", "b"), root), "named list")
  expect_error(check_static(list("a"), root), "named list")
  expect_error(check_static(list(x = "a", "b"), root), "named list")
  expect_error(check_static(stats::setNames(list("a"), ""), root), "named list")
  expect_error(check_static(list(x = "a", x = "b"), root), "more than once")
  expect_error(check_static(c("a", "b"), root), "`static` must be")
  expect_error(check_static(list(x = 1), root), "`static` must be")
})

test_that("a static name is one URL segment, not one Shiny serves", {
  root <- local_root("a")
  for (bad in c("a/b", "/a", "a b")) {
    expect_error(check_static(stats::setNames(list("a"), bad), root), "one URL segment",
                 info = bad)
  }
  for (reserved in c("session", "shared")) {
    expect_error(check_static(stats::setNames(list("a"), reserved), root),
                 "Shiny serves", info = reserved)
  }
})

test_that("a static dir that does not exist is an error naming root", {
  root <- local_root()
  expect_error(check_static("static", root),
               paste0("\"static\".*", regex_escape(root)))
  expect_error(check_static(list(js = "js"), root), "\"js\"")
})

test_that("a static path may not overlap the API prefix", {
  root <- local_root("a")
  expect_error(check_static(list(api = "a"), root, prefix = "/api"), "API prefix")
  expect_error(check_static(list(api = "a"), root, prefix = "/api/v1"), "API prefix")
  expect_identical(names(check_static(list(apis = "a"), root, prefix = "/api")), "/apis")
})

test_that("spigot_app() refuses a page at or under a static path", {
  root <- local_root("static")
  page <- spigot_page("<html><head></head><body></body></html>")
  for (path in c("/static", "/static/x")) {
    expect_error(
      spigot_app(pages = stats::setNames(list(page), path), api = test_router(),
                 static = "static", root = root),
      "under the static path \"/static\"", info = path
    )
  }
})

test_that("spigot_app() sets the static dirs on the server when the app starts", {
  root <- local_root("static")
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router(),
                    static = "static", root = root)
  paths <- start_with_server(app, fake_server())$calls()[[1]]
  expect_identical(names(paths), c("/static", "/api"))
  expect_identical(paths[["/static"]], httpuv::staticPath(file.path(root, "static")))

  # static = NULL: only the API exclusion, as in 0.1.1.
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router())
  expect_identical(names(start_with_server(app, fake_server())$calls()[[1]]), "/api")
})
