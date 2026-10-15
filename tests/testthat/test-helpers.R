test_that("fake_req() exposes a rewindable rook.input", {
  req <- fake_req("POST", "/x", body = "hello")
  expect_identical(req$rook.input$read(), charToRaw("hello"))
  expect_identical(req$rook.input$read(), raw(0))
  req$rook.input$rewind()
  expect_identical(req$rook.input$read(), charToRaw("hello"))
})

test_that("fake_req() reads in chunks and as lines", {
  req <- fake_req("POST", "/x", body = "ab\ncd")
  expect_identical(req$rook.input$read(2), charToRaw("ab"))
  req$rook.input$rewind()
  expect_identical(req$rook.input$read_lines(), c("ab", "cd"))
})

test_that("fake_req() maps headers, query and JSON bodies like httpuv", {
  req <- fake_req("POST", "/p", query = "a=1", body = list(k = 1),
                  headers = list(`X-Spigot-Session` = "abc", Origin = "http://h"))
  expect_identical(req$REQUEST_METHOD, "POST")
  expect_identical(req$PATH_INFO, "/p")
  expect_identical(req$SCRIPT_NAME, "")
  expect_identical(req$QUERY_STRING, "?a=1")
  expect_identical(req$HTTP_HOST, "127.0.0.1:1234")
  expect_identical(req$HTTP_X_SPIGOT_SESSION, "abc")
  expect_identical(req$HTTP_ORIGIN, "http://h")
  expect_identical(req$CONTENT_TYPE, "application/json")
  expect_identical(rawToChar(req$rook.input$read()), '{"k":1}')
})

test_that("fake_req() sets content headers both ways and HEADERS, as httpuv does", {
  req <- fake_req("POST", "/p", body = "abc", headers = list(`Content-Type` = "image/png"))
  expect_identical(req$CONTENT_TYPE, "image/png")
  expect_identical(req$HTTP_CONTENT_TYPE, "image/png")
  expect_identical(req$CONTENT_LENGTH, "3")
  expect_identical(req$HTTP_CONTENT_LENGTH, "3")
  expect_identical(req$HEADERS[["content-type"]], "image/png")
  expect_identical(req$HEADERS[["host"]], "127.0.0.1:1234")
})

test_that("fake_req() without a body has an empty input", {
  req <- fake_req()
  expect_identical(req$rook.input$read(), raw(0))
  expect_null(req$CONTENT_TYPE)
})
