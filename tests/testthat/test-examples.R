# Smoke test every bundled example against a real server. Each example needs
# an entry in `smoke`: a function(url, headers) holding its API checks.
# `headers` binds the calls to a live Shiny session (require_session = TRUE).

smoke <- list(
  minimal = function(u, h) {
    r <- hit(paste0(u, "/api/hello?name=Ada"), headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    expect_identical(httr2::resp_body_json(r)$message, "Hello, Ada!")

    r <- hit(paste0(u, "/api/echo"), "POST", json = list(a = 1, tags = list("x", "y")),
             headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    expect_identical(httr2::resp_body_json(r)$received, list(a = 1L, tags = list("x", "y")))

    r <- hit(paste0(u, "/api/summary?n=50"), headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    rows <- httr2::resp_body_json(r)$quantiles
    expect_length(rows, 5)
    expect_named(rows[[1]], c("p", "value"))

    r <- hit(paste0(u, "/api/summary?n=0"), headers = h)
    expect_identical(httr2::resp_status(r), 400L)
    expect_match(httr2::resp_body_json(r)$error, "n")

    t0 <- Sys.time()
    r <- hit(paste0(u, "/api/slow?seconds=0.5"), headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    expect_gte(as.numeric(Sys.time() - t0, units = "secs"), 0.5)

    r <- hit(paste0(u, "/app.js"))
    expect_identical(httr2::resp_status(r), 200L)
    expect_match(hit_text(r), "fetch(\"api/\"", fixed = TRUE)
    expect_match(hit_text(r), "X-Spigot-Session", fixed = TRUE)

    expect_identical(httr2::resp_status(hit(paste0(u, "/api/hello"))), 401L)
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
    sess <- open_session(srv$url)
    smoke[[name]](srv$url, list(`X-Spigot-Session` = sess$token))
  })
}

test_that("the minimal example's page calls its API from a browser", {
  skip_if_no_chrome()
  srv <- start_app(example_dir("minimal"))
  tab <- new_tab(srv$url)
  # api() is the page's own helper in www/app.js.
  r <- js(tab, 'api("GET", "hello?name=tab").then(r => ({status: r.status, msg: r.data.message}))')
  expect_identical(r, list(status = 200L, msg = "Hello, tab!"))
  r <- js(tab, 'api("POST", "echo", {k: 1}).then(r => r.status)')
  expect_identical(r, 200L)
})
