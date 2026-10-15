# ---- unit: registry -----------------------------------------------------------

test_that("a registered session can be looked up by its token", {
  s <- local_session()
  expect_identical(lookup_session(s$token), s)
})

test_that("an ended session is removed from the registry", {
  s <- fake_session()
  register_session(s)
  s$end()
  expect_null(lookup_session(s$token))
})

test_that("registering twice is idempotent", {
  s <- local_session()
  register_session(s)
  expect_identical(lookup_session(s$token), s)
  expect_identical(s$callbacks(), 1L)
  s$end()
  expect_null(lookup_session(s$token))
})

test_that("tokens are not case-folded", {
  s <- local_session()
  expect_null(lookup_session(toupper(s$token)))
})

test_that("unknown and malformed tokens look up as NULL", {
  expect_null(lookup_session(random_token()))
  for (t in list(NULL, NA_character_, "", "../x", c("a", "b"), 42, "abc")) {
    expect_null(lookup_session(t))
  }
})

test_that("a session that reports itself closed is not returned", {
  s <- local_session()
  s$isClosed <- function() TRUE
  expect_null(lookup_session(s$token))
})

test_that("ending one session leaves the others registered", {
  a <- local_session()
  b <- local_session()
  a$end()
  expect_null(lookup_session(a$token))
  expect_identical(lookup_session(b$token), b)
})

test_that("register_session() rejects a session without a valid token", {
  expect_error(register_session(fake_session("not-hex")), "token")
})

# ---- unit: server wrapper ------------------------------------------------------

test_that("wrap_server() has Shiny's formals and registers before the user server", {
  seen <- NULL
  f <- wrap_server(function(input, output, session) {
    seen <<- list(input = input, output = output, session = session,
                  registered = identical(lookup_session(session$token), session))
  })
  expect_named(formals(f), c("input", "output", "session"))
  s <- fake_session()
  withr::defer(s$end())
  f(input = "in", output = "out", session = s)
  expect_identical(seen$input, "in")
  expect_identical(seen$output, "out")
  expect_identical(seen$session, s)
  expect_true(seen$registered)
})

test_that("wrap_server() accepts a server without a session argument", {
  seen <- NULL
  f <- wrap_server(function(input, output) seen <<- list(input, output))
  s <- fake_session()
  withr::defer(s$end())
  f(input = "in", output = "out", session = s)
  expect_identical(seen, list("in", "out"))
  expect_identical(lookup_session(s$token), s)
})

test_that("wrap_server() passes clientData like Shiny does", {
  seen <- NULL
  f <- wrap_server(function(input, output, clientData) seen <<- clientData)
  s <- fake_session()
  s$clientData <- "cd"
  withr::defer(s$end())
  f(input = "in", output = "out", session = s)
  expect_identical(seen, "cd")
})

test_that("wrap_server(NULL) only registers the session", {
  f <- wrap_server(NULL)
  s <- fake_session()
  withr::defer(s$end())
  expect_no_error(f(input = "in", output = "out", session = s))
  expect_identical(lookup_session(s$token), s)
})

test_that("wrap_server() rejects a non-function", {
  expect_error(wrap_server("nope"), "server")
})

test_that("Shiny passes the session to the wrapped server", {
  args <- shiny:::argsForServerFunc(wrap_server(NULL), fake_session())
  expect_true("session" %in% names(args))
})

# ---- unit: spigot_session() ------------------------------------------------------

test_that("spigot_session() returns the bound session or NULL", {
  req <- fake_req()
  expect_null(spigot_session(req))
  s <- fake_session()
  req$spigot_session <- s
  expect_identical(spigot_session(req), s)
})

test_that("spigot_session() needs a request object", {
  expect_error(spigot_session(list()), "req")
  expect_error(spigot_session(NULL), "req")
  expect_error(spigot_session(new.env()), "req")
})

# ---- unit: guards through the mount handler ------------------------------------

# Router whose endpoint records what spigot_session(req) returned.
session_router <- function() {
  seen <- new.env()
  pr <- spigot_api() |>
    plumber::pr_get("/whoami", function(req) {
      s <- spigot_session(req)
      seen$session <- s
      list(token = if (is.null(s)) NULL else s$token)
    }) |>
    plumber::pr_post("/whoami", function(req) list(ok = TRUE))
  list(pr = pr, seen = seen)
}

guarded <- function(pr, require_session = TRUE) {
  spigot_mount_handler(pr, prefix = "/api", guard = request_guard(require_session))
}

test_that("a valid session header binds the session for the endpoint", {
  s <- local_session()
  rt <- session_router()
  r <- guarded(rt$pr)(fake_req("GET", "/api/whoami", headers = session_header(s)))
  expect_identical(r$status, 200L)
  expect_identical(resp_json(r), list(token = s$token))
  expect_identical(rt$seen$session, s)
})

test_that("missing, unknown, ended and malformed tokens get 401 JSON", {
  h <- guarded(session_router()$pr)
  ended <- fake_session()
  register_session(ended)
  ended$end()
  cases <- list(
    missing = list(),
    unknown = list(`X-Spigot-Session` = random_token()),
    ended = session_header(ended),
    upper = list(`X-Spigot-Session` = toupper(random_token())),
    traversal = list(`X-Spigot-Session` = "../x"),
    empty = list(`X-Spigot-Session` = "")
  )
  for (nm in names(cases)) {
    r <- h(fake_req("GET", "/api/whoami", headers = cases[[nm]]))
    expect_identical(r$status, 401L, info = nm)
    expect_identical(r$content_type, "application/json", info = nm)
    body <- resp_json(r)
    expect_named(body, c("error", "hint"), info = nm)
    expect_identical(body$error, "session required", info = nm)
    # The hint points developers at the setting, without explaining tokens.
    expect_identical(body$hint, SESSION_HINT, info = nm)
  }
})

test_that("the 401 hint names the setting and says nothing about tokens", {
  expect_match(SESSION_HINT, "spigot_app(..., require_session = FALSE)", fixed = TRUE)
  expect_no_match(SESSION_HINT, "token|X-Spigot-Session|sessionId", ignore.case = TRUE)
})

test_that("a malformed token is rejected without touching the registry", {
  local_mocked_bindings(lookup_session = function(token) stop("registry touched"))
  r <- guarded(session_router()$pr)(
    fake_req("GET", "/api/whoami", headers = list(`X-Spigot-Session` = "../x"))
  )
  expect_identical(r$status, 401L)
})

test_that("require_session = FALSE lets unbound requests through", {
  rt <- session_router()
  h <- guarded(rt$pr, require_session = FALSE)

  r <- h(fake_req("GET", "/api/whoami"))
  expect_identical(r$status, 200L)
  expect_null(rt$seen$session)
  expect_identical(resp_json(r), list(token = NULL))

  r <- h(fake_req("GET", "/api/whoami", headers = list(`X-Spigot-Session` = random_token())))
  expect_identical(r$status, 200L)
  expect_null(rt$seen$session)

  s <- local_session()
  r <- h(fake_req("GET", "/api/whoami", headers = session_header(s)))
  expect_identical(rt$seen$session, s)
})

test_that("cross-origin requests get 403 JSON", {
  s <- local_session()
  h <- guarded(session_router()$pr)
  cross <- list(
    origin = list(Origin = "http://evil.test"),
    origin_port = list(Origin = "http://127.0.0.1:9999"),
    origin_null = list(Origin = "null"),
    referer = list(Referer = "http://evil.test/page"),
    origin_wins = list(Origin = "http://evil.test", Referer = "http://127.0.0.1:1234/")
  )
  for (nm in names(cross)) {
    r <- h(fake_req("POST", "/api/whoami", headers = c(session_header(s), cross[[nm]])))
    expect_identical(r$status, 403L, info = nm)
    expect_identical(r$content_type, "application/json", info = nm)
    expect_identical(resp_json(r), list(error = "cross-origin request refused"), info = nm)
  }
})

test_that("same-origin and origin-less requests pass the origin check", {
  s <- local_session()
  h <- guarded(session_router()$pr)
  same <- list(
    none = list(),
    origin = list(Origin = "http://127.0.0.1:1234"),
    origin_case = list(Origin = "HTTP://127.0.0.1:1234"),
    referer = list(Referer = "http://127.0.0.1:1234/some/page?x=1")
  )
  for (nm in names(same)) {
    r <- h(fake_req("POST", "/api/whoami", headers = c(session_header(s), same[[nm]])))
    expect_identical(r$status, 200L, info = nm)
  }
})

test_that("the origin check compares against Host or X-Forwarded-Host", {
  g <- origin_guard()
  req <- function(...) fake_req("POST", "/api/x", headers = list(...))
  expect_null(g(req(Host = "example.com", Origin = "https://example.com")))
  expect_null(g(req(Host = "example.com", Origin = "https://example.com:443")))
  expect_null(g(req(Host = "example.com:80", Origin = "http://example.com")))
  expect_null(g(req(Host = "[::1]:8080", Origin = "http://[::1]:8080")))
  # Behind a proxy that rewrites Host to the upstream address.
  expect_null(g(req(Host = "127.0.0.1:3838", `X-Forwarded-Host` = "apps.example.com",
                    Origin = "https://apps.example.com")))
  expect_null(g(req(Host = "127.0.0.1:3838", `X-Forwarded-Host` = "apps.example.com, proxy.lan",
                    Origin = "https://apps.example.com")))
  expect_identical(g(req(Host = "127.0.0.1:3838", `X-Forwarded-Host` = "apps.example.com",
                         Origin = "https://evil.test"))$status, 403L)
  expect_identical(g(req(Host = "example.com", Origin = "https://example.com.evil.test"))$status, 403L)
  expect_identical(g(req(Host = "example.com", Origin = "https://user@evil.test"))$status, 403L)
  expect_identical(g(req(Host = "example.com", Origin = "not a url"))$status, 403L)
})

test_that("a request without Host but with Origin is refused", {
  req <- fake_req("POST", "/api/x", headers = list(Origin = "http://127.0.0.1:1234"))
  rm("HTTP_HOST", envir = req)
  expect_identical(origin_guard()(req)$status, 403L)
})

test_that("the origin check runs before the session check", {
  h <- guarded(session_router()$pr)
  r <- h(fake_req("POST", "/api/whoami", headers = list(Origin = "http://evil.test")))
  expect_identical(r$status, 403L)
})

test_that("guard rejections never reach the router", {
  calls <- 0L
  spy <- list(call = function(req) {
    calls <<- calls + 1L
    list(status = 200L, headers = list(), body = "")
  })
  h <- guarded(spy)
  expect_identical(h(fake_req("GET", "/api/x"))$status, 401L)
  expect_identical(h(fake_req("GET", "/api/x", headers = list(Origin = "http://evil.test")))$status, 403L)
  expect_identical(calls, 0L)
  s <- local_session()
  expect_identical(h(fake_req("GET", "/api/x", headers = session_header(s)))$status, 200L)
  expect_identical(calls, 1L)
})

test_that("guards do not apply outside the prefix", {
  h <- spigot_mount_handler(session_router()$pr, prefix = "/api",
                            fallback = function(req) "page", guard = request_guard(TRUE))
  expect_identical(h(fake_req("GET", "/", headers = list(Origin = "http://evil.test"))), "page")
})

test_that("request_guard() validates require_session", {
  expect_error(request_guard(NA), "require_session")
  expect_error(request_guard("yes"), "require_session")
  expect_error(request_guard(c(TRUE, FALSE)), "require_session")
})

# ---- integration: real httpuv and a real Shiny session -------------------------

test_that("a live session's token unlocks the API; others get 401", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "session"))
  u <- paste0(srv$url, "/api/whoami")
  sess <- open_session(srv$url)
  expect_match(sess$token, "^[0-9a-f]{32}$")

  r <- hit(u, headers = list(`X-Spigot-Session` = sess$token))
  expect_identical(httr2::resp_status(r), 200L)
  expect_identical(httr2::resp_body_json(r), list(token = sess$token))

  r <- hit(u, "POST", json = list(a = 1), headers = list(`X-Spigot-Session` = sess$token))
  expect_identical(httr2::resp_status(r), 200L)

  for (h in list(list(), list(`X-Spigot-Session` = random_token()))) {
    r <- hit(u, headers = h)
    expect_identical(httr2::resp_status(r), 401L)
    expect_identical(httr2::resp_body_json(r)$error, "session required")
    expect_identical(httr2::resp_body_json(r)$hint, SESSION_HINT)
  }
})

test_that("a token stops working within 1 s of its session ending", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "session"))
  u <- paste0(srv$url, "/api/whoami")
  sess <- open_session(srv$url)
  hdr <- list(`X-Spigot-Session` = sess$token)
  expect_identical(httr2::resp_status(hit(u, headers = hdr)), 200L)
  sess$close()
  expect_true(eventually(function() httr2::resp_status(hit(u, headers = hdr)) == 401L))
})

test_that("cross-origin requests get 403 over real HTTP", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "session"))
  u <- paste0(srv$url, "/api/whoami")
  sess <- open_session(srv$url)
  hdr <- list(`X-Spigot-Session` = sess$token)

  r <- hit(u, "POST", json = list(), headers = c(hdr, Origin = "http://evil.test"))
  expect_identical(httr2::resp_status(r), 403L)
  expect_identical(httr2::resp_body_json(r), list(error = "cross-origin request refused"))

  r <- hit(u, "POST", json = list(), headers = c(hdr, Origin = srv$url))
  expect_identical(httr2::resp_status(r), 200L)
})

test_that("an oversize body gets Shiny's plain-text 413", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "session")) # max_request_size = 1024
  sess <- open_session(srv$url)
  r <- hit(paste0(srv$url, "/api/whoami"), "POST", raw = charToRaw(strrep("x", 2048)),
           type = "text/plain", headers = list(`X-Spigot-Session` = sess$token))
  expect_identical(httr2::resp_status(r), 413L)
  expect_match(httr2::resp_content_type(r), "text/plain")
  expect_match(hit_text(r), "Maximum upload size exceeded")

  r <- hit(paste0(srv$url, "/api/whoami"), "POST", raw = charToRaw(strrep("x", 512)),
           type = "text/plain", headers = list(`X-Spigot-Session` = sess$token))
  expect_identical(httr2::resp_status(r), 200L)
})

# ---- e2e: Chrome ----------------------------------------------------------------

test_that("a browser tab can call the API with its session token", {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "session"))
  tab <- new_tab(srv$url)
  token <- js(tab, "Shiny.shinyapp.config.sessionId")

  call <- function(method) sprintf(
    'fetch("api/whoami", {method: "%s", headers: {"X-Spigot-Session": Shiny.shinyapp.config.sessionId,
       "Content-Type": "application/json"}%s})
       .then(r => r.json().then(b => ({status: r.status, token: b.token})))',
    method, if (method == "POST") ', body: "{}"' else ""
  )
  # A browser POST carries a same-origin Origin header; it must pass the guard.
  for (m in c("GET", "POST")) {
    r <- js(tab, call(m))
    expect_identical(r$status, 200L, info = m)
    expect_identical(r$token, token, info = m)
  }
  r <- js(tab, 'fetch("api/whoami").then(r => r.status)')
  expect_identical(r, 401L)

  tab$close()
  hdr <- list(`X-Spigot-Session` = token)
  u <- paste0(srv$url, "/api/whoami")
  expect_true(eventually(function() httr2::resp_status(hit(u, headers = hdr)) == 401L))
})
