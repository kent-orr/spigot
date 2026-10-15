# Smoke test every bundled example against a real server. Each example needs
# an entry in `smoke`: a function(url) holding its API checks.

smoke <- list(
  minimal = function(u) {
    r <- hit(paste0(u, "/api/hello?name=Ada"))
    expect_identical(httr2::resp_status(r), 200L)
    expect_identical(httr2::resp_body_json(r)$message, "Hello, Ada!")

    r <- hit(paste0(u, "/api/echo"), "POST", json = list(a = 1, tags = list("x", "y")))
    expect_identical(httr2::resp_status(r), 200L)
    expect_identical(httr2::resp_body_json(r)$received, list(a = 1L, tags = list("x", "y")))

    r <- hit(paste0(u, "/api/summary?n=50"))
    expect_identical(httr2::resp_status(r), 200L)
    rows <- httr2::resp_body_json(r)$quantiles
    expect_length(rows, 5)
    expect_named(rows[[1]], c("p", "value"))

    r <- hit(paste0(u, "/api/summary?n=0"))
    expect_identical(httr2::resp_status(r), 400L)
    expect_match(httr2::resp_body_json(r)$error, "n")

    t0 <- Sys.time()
    r <- hit(paste0(u, "/api/slow?seconds=0.5"))
    expect_identical(httr2::resp_status(r), 200L)
    expect_gte(as.numeric(Sys.time() - t0, units = "secs"), 0.5)

    r <- hit(paste0(u, "/app.js"))
    expect_identical(httr2::resp_status(r), 200L)
    expect_match(hit_text(r), "fetch(\"api/\"", fixed = TRUE)
  }
)

test_that("every bundled example has a smoke test", {
  expect_setequal(available_examples(), names(smoke))
})

for (name in names(smoke)) {
  test_that(paste("example", name, "serves its page and API"), {
    skip_on_cran()
    srv <- start_app(example_dir(name))
    r <- hit(paste0(srv$url, "/"))
    expect_identical(httr2::resp_status(r), 200L)
    page <- hit_text(r)
    expect_match(page, "app.js", fixed = TRUE)
    expect_match(page, "shiny", fixed = TRUE)
    smoke[[name]](srv$url)
  })
}
