# Scalar checks in R/utils.R.

test_that("is_string() accepts one non-NA string", {
  expect_true(is_string("a"))
  expect_true(is_string(""))
  for (bad in list(NA_character_, character(0), c("a", "b"), 1, NULL, NA, list("a"))) {
    expect_false(is_string(bad))
  }
})

test_that("is_flag() accepts one non-NA logical", {
  expect_true(is_flag(TRUE))
  expect_true(is_flag(FALSE))
  for (bad in list(NA, logical(0), c(TRUE, FALSE), 1, "TRUE", NULL)) {
    expect_false(is_flag(bad))
  }
})
