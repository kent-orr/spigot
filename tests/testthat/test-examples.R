# Smoke test every bundled example against a real server. Each example needs
# an entry in `smoke`: a function(url, headers, session) holding its API
# checks. `headers` binds the calls to `session`, a live Shiny session opened
# without a browser (open_session()), as require_session = TRUE needs.
# `needs` lists the Suggests packages an example uses.

needs <- list(site = "future")

# The value of the last pushed `event` that `sess` received, or NULL.
last_push <- function(sess, event) {
  got <- Filter(function(m) identical(m$event, event), sess$custom("spigot:event"))
  if (!length(got)) return(NULL)
  jsonlite::fromJSON(got[[length(got)]]$json, simplifyVector = FALSE)
}

smoke <- list(
  minimal = function(u, h, sess) {
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
    expect_match(hit_text(hit(paste0(u, "/"))), "app.js", fixed = TRUE)
    r <- hit(paste0(u, "/app.js"))
    expect_identical(httr2::resp_status(r), 200L)
    expect_match(hit_text(r), "spigot.get(", fixed = TRUE)
    expect_match(hit_text(r), "spigot.post(", fixed = TRUE)
    expect_no_match(hit_text(r), "fetch(", fixed = TRUE)
    expect_no_match(hit_text(r), "X-Spigot-Session", fixed = TRUE)

    expect_identical(httr2::resp_status(hit(paste0(u, "/api/hello"))), 401L)
  },

  live = function(u, h, sess) {
    r <- hit(paste0(u, "/api/state"), headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    state <- httr2::resp_body_json(r)
    expect_gte(state$tabs, 1L)

    r <- hit(paste0(u, "/api/increment"), "POST", json = list(by = 2), headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    expect_identical(httr2::resp_body_json(r)$count, state$count + 2L)
    # Every tab is told the new count; the calling tab's server function is
    # also told, through an input.
    expect_identical(last_push(sess, "count")$count, state$count + 2L)
    expect_length(sess$custom("spigot:set-input"), 1)

    r <- hit(paste0(u, "/api/increment"), "POST", json = list(by = 0), headers = h)
    expect_identical(httr2::resp_status(r), 400L)
    r <- hit(paste0(u, "/api/increment"), "POST", json = list(by = "x"), headers = h)
    expect_identical(httr2::resp_status(r), 400L)
    expect_identical(httr2::resp_body_json(hit(paste0(u, "/api/state"), headers = h))$count,
                     state$count + 2L)

    expect_identical(httr2::resp_status(hit(paste0(u, "/api/state"))), 401L)
  },

  site = function(u, h, sess) {
    pages <- c(home = "/", cars = "/cars", model = "/model")
    for (key in names(pages)) {
      r <- hit(paste0(u, pages[[key]]))
      expect_identical(httr2::resp_status(r), 200L)
      html <- hit_text(r)
      # Every page shares the nav and footer partials; the nav marks the
      # current page.
      expect_match(html, 'class="site-nav"', fixed = TRUE)
      expect_match(html, 'class="site-footer"', fixed = TRUE)
      expect_match(html, sprintf('data-page="%s" aria-current="page"', key), fixed = TRUE)
      expect_identical(lengths(regmatches(html, gregexpr('aria-current="page"', html))), 1L)
    }
    # The cars page is rendered in R: every row is in the HTML.
    cars <- hit_text(hit(paste0(u, "/cars")))
    expect_identical(lengths(regmatches(cars, gregexpr("<tr data-car=", cars))), 32L)

    # Scripts and the stylesheet come from static/: the app's at /static, each
    # blueprint's at <prefix>/static, which its pages see as {{static}}.
    expect_match(cars, '<link rel="stylesheet" href="static/site.css">', fixed = TRUE)
    expect_match(cars, '<script src="cars/static/cars.js"></script>', fixed = TRUE)
    expect_match(hit_text(hit(paste0(u, "/model"))), '<script src="model/static/model.js"></script>',
                 fixed = TRUE)
    for (f in c("static/site.css", "cars/static/cars.js", "model/static/model.js")) {
      r <- hit(paste0(u, "/", f))
      expect_identical(httr2::resp_status(r), 200L, info = f)
      expect_match(httr2::resp_content_type(r), "css|javascript", info = f)
    }

    r <- hit(paste0(u, "/api/cars?q=merc"), headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    rows <- httr2::resp_body_json(r)$rows
    expect_length(rows, 7)
    expect_true(all(grepl("^Merc", vapply(rows, `[[`, "", "model"))))
    rows <- httr2::resp_body_json(hit(paste0(u, "/api/cars?min_mpg=30"), headers = h))$rows
    expect_length(rows, 4)
    expect_true(all(vapply(rows, `[[`, 0, "mpg") >= 30))

    # The fit runs in a future worker, another R process.
    r <- hit(paste0(u, "/api/fit"), "POST", json = list(x = "wt", reps = 200), headers = h)
    expect_identical(httr2::resp_status(r), 200L)
    fit <- httr2::resp_body_json(r)
    expect_identical(fit$x, "wt")
    expect_identical(fit$reps, 200L)
    expect_lt(fit$slope$estimate, 0)
    expect_lt(fit$slope$lower, fit$slope$upper)
    expect_false(identical(fit$worker_pid, fit$app_pid))

    r <- hit(paste0(u, "/api/fit"), "POST", json = list(x = "nope"), headers = h)
    expect_identical(httr2::resp_status(r), 400L)
    expect_match(httr2::resp_body_json(r)$error, "x")

    expect_identical(httr2::resp_status(hit(paste0(u, "/missing"))), 404L)
  }
)

test_that("every bundled example has a smoke test", {
  expect_setequal(available_examples(), names(smoke))
})

for (name in names(smoke)) {
  test_that(paste("example", name, "serves its page and API"), {
    skip_on_cran()
    for (pkg in needs[[name]]) skip_if_not_installed(pkg)
    srv <- start_app(example_dir(name), timeout = 30)
    r <- hit(paste0(srv$url, "/"))
    expect_identical(httr2::resp_status(r), 200L)
    page <- hit_text(r)
    expect_match(page, "spigot.js", fixed = TRUE)
    expect_match(page, "shiny", fixed = TRUE)
    sess <- open_session(srv$url)
    smoke[[name]](srv$url, list(`X-Spigot-Session` = sess$token), sess)
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

# Wait until `expr` (JS) in `tab` returns something matching `pattern`.
wait_for_text <- function(tab, expr, pattern, timeout = 5) {
  deadline <- Sys.time() + timeout
  repeat {
    txt <- js(tab, expr)
    if (is.character(txt) && grepl(pattern, txt, perl = TRUE)) return(txt)
    if (Sys.time() > deadline) return(txt)
    Sys.sleep(0.05)
  }
}

test_that("the live example pushes the count to every tab and updates the caller's output", {
  skip_if_no_chrome()
  srv <- start_app(example_dir("live"))
  a <- new_tab(srv$url)
  b <- new_tab(srv$url)
  text <- function(id) sprintf('document.getElementById("%s").textContent', id)
  # Both tabs show the shared count and that two tabs are open.
  expect_match(wait_for_text(a, text("count"), "^0$"), "^0$")
  expect_match(wait_for_text(a, text("tabs"), "^2$"), "^2$")
  # The tab output is a Shiny output that the server function renders.
  expect_match(wait_for_text(a, text("mine"), "^0$"), "^0$")

  js(a, 'document.getElementById("plus-one").click(); true')
  js(a, 'document.getElementById("plus-one").click(); true')
  js(b, 'document.getElementById("plus-five").click(); true')
  expect_match(wait_for_text(a, text("count"), "^7$"), "^7$")
  expect_match(wait_for_text(b, text("count"), "^7$"), "^7$")
  # Each tab's own clicks reach only its own server function.
  expect_match(wait_for_text(a, text("mine"), "^2$"), "^2$")
  expect_match(wait_for_text(b, text("mine"), "^5$"), "^5$")

  b$close()
  expect_match(wait_for_text(a, text("tabs"), "^1$"), "^1$")
})

test_that("the live example's tab count survives a state reply that arrives late", {
  skip_if_no_chrome()
  srv <- start_app(example_dir("live"))
  # Hold tab a's reply to `state` (sent with one tab open) until after tab b
  # has opened and the push of the new count has reached a.
  hold <- '(() => {
    const f = window.fetch;
    window.fetch = (url, init) => {
      const p = f(url, init);
      if (!/\\/api\\/state$/.test(String(url))) return p;
      return p.then((r) => new Promise((ok) => setTimeout(() => {
        window.stateLanded = true; ok(r); }, 3000)));
    };
  })();'
  a <- new_tab(srv$url, init = hold)
  b <- new_tab(srv$url)
  text <- 'document.getElementById("tabs").textContent'
  expect_match(wait_for_text(a, text, "^2$"), "^2$")
  expect_match(wait_for_text(a, "String(window.stateLanded === true)", "^true$"), "^true$")
  Sys.sleep(0.5) # let the page handle the reply
  expect_identical(js(a, text), "2")
})

test_that("the site example filters cars and fits a model from the browser", {
  skip_if_no_chrome()
  skip_if_not_installed("future")
  srv <- start_app(example_dir("site"), timeout = 30)
  tab <- new_tab(paste0(srv$url, "/cars"))
  rows <- 'String(document.querySelectorAll("#cars tbody tr").length)'
  expect_identical(js(tab, rows), "32")
  js(tab, 'document.getElementById("q").value = "toyota"; true')
  js(tab, 'document.querySelector("#filter button").click(); true')
  expect_match(wait_for_text(tab, rows, "^2$"), "^2$")

  # Links between pages are relative and work in the browser.
  loaded <- tab$Page$loadEventFired(wait_ = FALSE)
  js(tab, 'document.querySelector(".site-nav a[data-page=model]").click(); true')
  tab$wait_for(loaded)
  ready <- "!!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.config && Shiny.shinyapp.config.sessionId)"
  expect_true(eventually(function() js(tab, ready), timeout = 10))
  expect_match(js(tab, "location.pathname"), "/model$")
  js(tab, 'document.querySelector("#fit button").click(); true')
  out <- wait_for_text(tab, 'document.getElementById("fit-out").textContent',
                       "slope", timeout = 30)
  expect_match(out, "slope")
  expect_match(out, "worker")
})
