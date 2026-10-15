test_that("Content-Type moves from headers to content_type", {
  r <- rook_to_httpResponse(list(
    status = 200L,
    headers = list(`Content-Type` = "application/json", `Cache-Control` = "no-store"),
    body = '{"a":1}'
  ))
  expect_s3_class(r, "httpResponse")
  expect_identical(r$status, 200L)
  expect_identical(r$content_type, "application/json")
  expect_false(any(tolower(names(r$headers)) == "content-type"))
  expect_identical(r$headers$`Cache-Control`, "no-store")
  expect_identical(r$content, '{"a":1}')
})

test_that("status is an integer", {
  r <- rook_to_httpResponse(list(status = 404, headers = list(), body = "x"))
  expect_identical(r$status, 404L)
})

test_that("Content-Type is matched case-insensitively", {
  r <- rook_to_httpResponse(list(status = 200L, headers = list(`content-type` = "text/csv"),
                                 body = "a,b"))
  expect_identical(r$content_type, "text/csv")
  expect_length(names(r$headers)[tolower(names(r$headers)) == "content-type"], 0)
})

test_that("missing Content-Type falls back on the body type", {
  raw_r <- rook_to_httpResponse(list(status = 200L, headers = list(), body = as.raw(1:3)))
  expect_identical(raw_r$content_type, "application/octet-stream")
  chr_r <- rook_to_httpResponse(list(status = 200L, headers = list(), body = "x"))
  expect_identical(chr_r$content_type, "text/plain")
  null_hdr <- rook_to_httpResponse(list(status = 200L, headers = NULL, body = "x"))
  expect_identical(null_hdr$content_type, "text/plain")
})

test_that("NULL body (204) becomes an empty string", {
  r <- rook_to_httpResponse(list(status = 204L, headers = list(), body = NULL))
  expect_identical(r$status, 204L)
  expect_identical(r$content, "")
})

test_that("raw bodies pass through byte-exact", {
  bytes <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x00, 0xff))
  r <- rook_to_httpResponse(list(status = 200L,
                                 headers = list(`Content-Type` = "image/png"), body = bytes))
  expect_identical(r$content, bytes)
})

test_that("character bodies are UTF-8", {
  s <- "Gr\xf6\xdfe"
  Encoding(s) <- "latin1"
  r <- rook_to_httpResponse(list(status = 200L, headers = list(), body = s))
  expect_identical(Encoding(r$content), "UTF-8")
  expect_identical(charToRaw(r$content), charToRaw(enc2utf8(s)))
})

test_that("other headers survive and nosniff is added", {
  r <- rook_to_httpResponse(list(
    status = 200L,
    headers = list(`Set-Cookie` = "a=1", `Content-Type` = "text/plain"),
    body = "x"
  ))
  expect_identical(r$headers$`Set-Cookie`, "a=1")
  expect_identical(r$headers$`X-Content-Type-Options`, "nosniff")
})

test_that("json_error() builds a JSON httpResponse", {
  r <- json_error(401L, "session required")
  expect_s3_class(r, "httpResponse")
  expect_identical(r$status, 401L)
  expect_identical(r$content_type, "application/json")
  expect_identical(resp_json(r), list(error = "session required"))
})

test_that("json_error() can add a hint", {
  r <- json_error(401L, "session required", hint = "send a token")
  expect_identical(resp_json(r), list(error = "session required", hint = "send a token"))
})
