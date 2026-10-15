test_that("spigot_api() builds a router from a plumber file", {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(c("#* @get /hi", "function() list(msg = 'hi')"), f)
  pr <- spigot_api(f)
  expect_s3_class(pr, "Plumber")
  r <- pr$call(fake_req("GET", "/hi"))
  expect_identical(r$status, 200L)
  expect_identical(as.character(r$body), '{"msg":"hi"}')
})

test_that("spigot_api() evaluates the file in `envir`", {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(c("#* @get /v", "function() list(v = secret)"), f)
  e <- new.env()
  e$secret <- 42
  r <- spigot_api(f, envir = e)$call(fake_req("GET", "/v"))
  expect_identical(as.character(r$body), '{"v":42}')
})

default_serializer <- function(pr) pr$.__enclos_env__$private$default_serializer

test_that("spigot_api() returns a Plumber object unchanged", {
  pr <- plumber::pr()
  before <- default_serializer(pr)
  expect_identical(spigot_api(pr), pr)
  expect_identical(default_serializer(pr), before)
})

test_that("spigot_api() with no file is an empty router using spigot_json()", {
  pr <- spigot_api()
  expect_s3_class(pr, "Plumber")
  expect_length(pr$endpoints, 0)
  pr <- pr |>
    plumber::pr_get("/x", function() list(a = 1, b = I(2), c = NA, t = as.Date("2026-10-15")))
  r <- pr$call(fake_req("GET", "/x"))
  expect_identical(as.character(r$body), as.character(spigot_json(
    list(a = 1, b = I(2), c = NA, t = as.Date("2026-10-15"))
  )))
  expect_identical(r$headers$`Content-Type`, "application/json")
})

test_that("file endpoints with their own serializer keep it", {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(c("#* @get /t", "#* @serializer text", "function() 'plain'"), f)
  r <- spigot_api(f)$call(fake_req("GET", "/t"))
  expect_match(r$headers$`Content-Type`, "^text/plain")
  expect_identical(as.character(r$body), "plain")
})

test_that("spigot_api() rejects anything else", {
  expect_error(spigot_api(42), "plumber")
  expect_error(spigot_api("no/such/file.R"), "no/such/file.R")
})
