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

    # The page uses spigot.js, not hand-rolled fetch() calls.
    r <- hit(paste0(u, "/app.js"))
    expect_identical(httr2::resp_status(r), 200L)
    expect_match(hit_text(r), "spigot.get(", fixed = TRUE)
    expect_match(hit_text(r), "spigot.post(", fixed = TRUE)
    expect_no_match(hit_text(r), "fetch(", fixed = TRUE)
    expect_no_match(hit_text(r), "X-Spigot-Session", fixed = TRUE)

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
    expect_match(page, "spigot.js", fixed = TRUE)
    expect_match(page, "shiny", fixed = TRUE)
    sess <- open_session(srv$url)
    smoke[[name]](srv$url, list(`X-Spigot-Session` = sess$token))
  })
}

test_that("the minimal example's page calls its API from a browser", {
  skip_if_no_chrome()
  srv <- start_app(example_dir("minimal"))
  tab <- new_tab(srv$url)
  # Drive the page's own buttons and read what it shows.
  click_and_read <- function(form, out) {
    js(tab, sprintf('document.getElementById("%s").textContent = ""; true', out))
    js(tab, sprintf('document.querySelector("#%s button").click(); true', form))
    deadline <- Sys.time() + 5
    repeat {
      txt <- js(tab, sprintf('document.getElementById("%s").textContent', out))
      if (nzchar(txt) || Sys.time() > deadline) return(txt)
      Sys.sleep(0.05)
    }
  }
  js(tab, 'document.getElementById("hello-name").value = "tab"; true')
  expect_match(click_and_read("hello-form", "hello-out"), "OK[\\s\\S]*Hello, tab!", perl = TRUE)
  expect_match(click_and_read("echo-form", "echo-out"), "OK[\\s\\S]*RKS0420", perl = TRUE)
  js(tab, 'document.getElementById("summary-n").value = "0"; true')
  out <- click_and_read("summary-form", "summary-out")
  expect_match(out, "400[\\s\\S]*n must be a whole number", perl = TRUE)
  expect_true(js(tab, 'document.getElementById("summary-out").classList.contains("err")'))
})
