test_that("example_dir() finds a bundled example", {
  d <- example_dir("minimal")
  expect_true(dir.exists(d))
  expect_true(file.exists(file.path(d, "app.R")))
})

test_that("available_examples() lists the bundled examples", {
  expect_true("minimal" %in% available_examples())
})

test_that("an unknown example name errors and lists the available ones", {
  expect_error(example_dir("nope"), "nope")
  expect_error(example_dir("nope"), "minimal")
  expect_error(example_dir(c("a", "b")), "single")
  expect_error(example_dir(NA_character_), "single")
})

test_that("run_example() hands the example directory and options to runApp()", {
  seen <- NULL
  local_mocked_bindings(runApp = function(appDir, ...) {
    seen <<- list(appDir = appDir, dots = list(...))
    "ran"
  }, .package = "shiny")
  expect_identical(run_example("minimal", port = 1234, launch.browser = FALSE), "ran")
  expect_identical(seen$appDir, example_dir("minimal"))
  expect_identical(seen$dots, list(port = 1234, launch.browser = FALSE))
})

test_that("run_example() defaults to the minimal example", {
  seen <- NULL
  local_mocked_bindings(runApp = function(appDir, ...) seen <<- appDir, .package = "shiny")
  run_example()
  expect_identical(seen, example_dir("minimal"))
})
