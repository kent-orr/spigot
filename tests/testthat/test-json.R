j <- function(x) as.character(spigot_json(x))

test_that("scalars are unboxed", {
  expect_identical(j(1), "1")
  expect_identical(j("a"), '"a"')
  expect_identical(j(TRUE), "true")
  expect_identical(j(list(a = 1, b = "x")), '{"a":1,"b":"x"}')
})

test_that("I() keeps a length-1 array", {
  expect_identical(j(I(1)), "[1]")
  expect_identical(j(list(a = I("x"))), '{"a":["x"]}')
})

test_that("NA and NULL become null", {
  expect_identical(j(NA), "null")
  expect_identical(j(NULL), "null")
  expect_identical(j(list(a = NULL, b = NA_character_, c = NA_real_)),
                   '{"a":null,"b":null,"c":null}')
  expect_identical(j(c(1, NA)), "[1,null]")
})

test_that("nested lists and empty vectors keep their shape", {
  expect_identical(j(list(a = list(b = list(c = 1:2)))), '{"a":{"b":{"c":[1,2]}}}')
  expect_identical(j(character(0)), "[]")
  expect_identical(j(list()), "[]")
  expect_identical(j(setNames(list(), character(0))), "{}")
})

test_that("data frames become arrays of row objects", {
  df <- data.frame(a = 1:2, b = c("x", NA))
  expect_identical(j(df), '[{"a":1,"b":"x"},{"a":2,"b":null}]')
})

test_that("numbers keep full precision", {
  expect_identical(j(1 / 3), "0.333333333333333")
  expect_identical(j(123456789.123), "123456789.123")
})

test_that("dates and times become ISO 8601 strings, times in UTC", {
  expect_identical(j(as.Date("2026-10-15")), '"2026-10-15"')
  t <- as.POSIXct("2026-10-15 12:34:56", tz = "America/New_York")
  expect_identical(j(t), '"2026-10-15T16:34:56Z"')
})

test_that("output is a single UTF-8 string", {
  out <- spigot_json(list(s = "Größe – ✓"))
  expect_length(out, 1)
  expect_identical(jsonlite::fromJSON(out)$s, "Größe – ✓")
})
