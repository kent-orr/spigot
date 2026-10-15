test_that("spigot_app() returns a shiny.appobj with the API mounted", {
  app <- spigot_app(ui = shiny::fluidPage("x"), api = test_router())
  expect_s3_class(app, "shiny.appobj")
  r <- app$httpHandler(fake_req("GET", "/api/items"))
  expect_identical(r$status, 200L)
  expect_identical(resp_text(r), "[1,2,3]")
})

test_that("spigot_app() honours a custom prefix", {
  app <- spigot_app(ui = shiny::fluidPage("x"), api = test_router(), prefix = "/rpc")
  expect_identical(app$httpHandler(fake_req("GET", "/rpc/items"))$status, 200L)
})

test_that("spigot_app() accepts a plumber file and applies spigot_json()", {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(c("#* @get /hi", "function() list(ok = TRUE)"), f)
  app <- spigot_app(ui = shiny::fluidPage("x"), api = f)
  expect_identical(resp_text(app$httpHandler(fake_req("GET", "/api/hi"))), '{"ok":true}')
})

test_that("spigot_app() serves a Plumber router as given", {
  pr <- plumber::pr() |> plumber::pr_get("/b", function() list(x = 1))
  app <- spigot_app(ui = shiny::fluidPage("x"), api = pr)
  expect_identical(resp_text(app$httpHandler(fake_req("GET", "/api/b"))), '{"x":[1]}')
})

test_that("spigot_app() validates its arguments", {
  expect_error(spigot_app(ui = shiny::fluidPage("x")), "api")
  expect_error(spigot_app(ui = shiny::fluidPage("x"), api = test_router(), prefix = "api"), "prefix")
})
