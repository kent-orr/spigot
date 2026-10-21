# How a spigot app behaves under each way of launching it. The fixture
# apps/launch/ uses everything a launch mode can leave out: a template file
# (index.html), a plumber file (api.R), a www/ file (app.js) and a helper in
# R/ (shout(), which api.R calls). It also has spigot's static/ (extra.js),
# which both modes serve.
#
# Directory mode is shiny::runApp("<dir>") or runApp("<dir>/app.R"), and what
# RStudio's Run App button, Shiny Server, Posit Connect and run_example() do.
# Shiny sources app.R in the directory after loading R/, serves www/, and runs
# the app with the directory as the working directory.
#
# Object mode is running the shiny.appobj that app.R returns. That is what
# printing it does (at the console, sourcing with echo, or `Rscript app.R`).
# Shiny then does none of the above.

launch_dir <- function() normalizePath(test_path("apps", "launch"))

# static/ is served by spigot in either mode, with a JavaScript content type.
expect_static_served <- function(srv) {
  r <- hit(paste0(srv$url, "/static/extra.js"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(httr2::resp_content_type(r), "javascript")
  expect_match(hit_text(r), "launchExtra", fixed = TRUE)
}

# The checks every directory-mode launch must pass.
expect_directory_mode <- function(srv, dir) {
  r <- hit(paste0(srv$url, "/"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(hit_text(r), "<title>launch fixture</title>", fixed = TRUE)
  expect_match(hit_text(r), "spigot.js", fixed = TRUE)

  r <- hit(paste0(srv$url, "/app.js"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(httr2::resp_content_type(r), "javascript")
  expect_match(hit_text(r), "launchFixture", fixed = TRUE)

  r <- hit(paste0(srv$url, "/api/shout?word=ok"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_identical(httr2::resp_body_json(r)$word, "OK")

  r <- hit(paste0(srv$url, "/api/wd"))
  expect_identical(httr2::resp_body_json(r)$wd, dir)

  expect_static_served(srv)
}

test_that("runApp(<dir>) serves the page, www/ files and R/ helpers", {
  skip_on_cran()
  dir <- launch_dir()
  expect_directory_mode(start_app(dir), dir)
})

test_that("runApp(<dir>/app.R) is the same as running the directory", {
  skip_on_cran()
  dir <- launch_dir()
  expect_directory_mode(start_app(file.path(dir, "app.R")), dir)
})

test_that("runApp(<dir>) works from another working directory", {
  skip_on_cran()
  dir <- launch_dir()
  expect_directory_mode(start_app(dir, wd = withr::local_tempdir()), dir)
})

test_that("printing a spigot app runs it as an object", {
  seen <- NULL
  local_mocked_bindings(runApp = function(appDir, ...) seen <<- appDir, .package = "shiny")
  app <- spigot_app(pages = shiny::fluidPage("x"), api = test_router())
  print(app)
  expect_identical(seen, app)
})

test_that("the object app.R returns serves its page and API, but not www/ or R/", {
  skip_on_cran()
  dir <- launch_dir()
  srv <- start_app(function() source("app.R")$value, wd = dir)

  # The template and plumber file are read relative to the working directory.
  r <- hit(paste0(srv$url, "/"))
  expect_identical(httr2::resp_status(r), 200L)
  expect_match(hit_text(r), "<title>launch fixture</title>", fixed = TRUE)
  expect_identical(httr2::resp_body_json(hit(paste0(srv$url, "/api/wd")))$wd, dir)

  # static/ is spigot's, so it is served here too.
  expect_static_served(srv)

  # www/ is not served: app.js gets spigot's HTML 404, which a browser
  # refuses to run as a script ("blocked due to MIME type").
  r <- hit(paste0(srv$url, "/app.js"))
  expect_identical(httr2::resp_status(r), 404L)
  expect_match(httr2::resp_content_type(r), "text/html")

  # R/ is not loaded: an endpoint calling shout() fails.
  r <- hit(paste0(srv$url, "/api/shout?word=ok"))
  expect_identical(httr2::resp_status(r), 500L)
  expect_match(httr2::resp_content_type(r), "application/json")
})

test_that("sourcing app.R from another directory can't find its files", {
  app_r <- file.path(launch_dir(), "app.R")
  withr::local_dir(withr::local_tempdir())
  expect_error(source(app_r, local = new.env()), "Can't find the template file \"index.html\"")
})
