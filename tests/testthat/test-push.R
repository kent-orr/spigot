# Server push: spigot_emit(), spigot_broadcast() and spigot.on() (PLAN M4).

# The spigot:event messages a fake session was sent, with `json` parsed.
events <- function(s) {
  sent <- Filter(function(m) identical(m$type, "spigot:event"), s$sent())
  lapply(sent, function(m) {
    list(event = m$message$event, json = m$message$json,
         data = jsonlite::fromJSON(m$message$json, simplifyVector = FALSE))
  })
}

# ---- unit: spigot_emit() --------------------------------------------------------

test_that("spigot_emit() sends one spigot:event message with a JSON string", {
  s <- fake_session()
  spigot_emit(s, "cart:changed", list(n = 1))
  sent <- s$sent()
  expect_length(sent, 1)
  expect_identical(sent[[1]]$type, "spigot:event")
  expect_named(sent[[1]]$message, c("event", "json"))
  expect_identical(sent[[1]]$message$event, "cart:changed")
  json <- sent[[1]]$message$json
  # A plain string, so Shiny's own toJSON() cannot reshape the payload.
  expect_true(is.character(json) && length(json) == 1 && !inherits(json, "json"))
  expect_identical(json, '{"n":1}')
})

test_that("spigot_emit() sends null when there is no data", {
  s <- fake_session()
  spigot_emit(s, "tick")
  expect_identical(events(s)[[1]]$json, "null")
})

test_that("spigot_emit() returns invisibly whether it sent", {
  s <- fake_session()
  expect_invisible(spigot_emit(s, "x", 1))
  expect_true(spigot_emit(s, "x", 1))
})

test_that("spigot_emit() without a session warns and sends nothing", {
  expect_warning(out <- spigot_emit(NULL, "cart:changed", 1), "no session")
  expect_false(out)
})

test_that("spigot_emit() checks its arguments", {
  s <- fake_session()
  for (bad in list(NULL, NA_character_, "", c("a", "b"), 1)) {
    expect_error(spigot_emit(s, bad, 1), "event")
  }
  expect_error(spigot_emit(list(token = "x"), "e", 1), "session")
  expect_length(s$sent(), 0)
})

test_that("spigot_emit() does not touch the registry", {
  s <- fake_session()
  spigot_emit(s, "e", 1)
  expect_null(lookup_session(s$token))
})

# ---- unit: spigot_broadcast() ---------------------------------------------------

test_that("spigot_broadcast() reaches every live session", {
  ss <- list(local_session(), local_session(), local_session())
  n <- spigot_broadcast("news", list(id = 7))
  expect_gte(n, 3)
  for (s in ss) {
    e <- events(s)
    expect_length(e, 1)
    expect_identical(e[[1]]$event, "news")
    expect_identical(e[[1]]$json, '{"id":7}')
  }
})

test_that("a session that has ended no longer receives broadcasts", {
  a <- local_session()
  b <- local_session()
  c <- local_session()
  b$end()
  spigot_broadcast("news", 1)
  expect_length(events(a), 1)
  expect_length(events(b), 0)
  expect_length(events(c), 1)
})

test_that("a session whose send fails is pruned and the others still receive", {
  a <- local_session()
  bad <- local_session()
  c <- local_session()
  bad$sendCustomMessage <- function(type, message) stop("socket closed")
  expect_no_error(expect_no_warning(spigot_broadcast("news", 1)))
  expect_length(events(a), 1)
  expect_length(events(c), 1)
  expect_null(lookup_session(bad$token))
  expect_length(events(a), 1)
  spigot_broadcast("news", 2)
  expect_length(events(a), 2)
})

test_that("a session that reports itself closed is skipped and pruned", {
  a <- local_session()
  closed <- local_session()
  closed$isClosed <- function() TRUE
  spigot_broadcast("news", 1)
  expect_length(events(closed), 0)
  expect_length(events(a), 1)
  expect_false(exists(closed$token, envir = .registry, inherits = FALSE))
})

test_that("spigot_broadcast() counts the sessions it reached", {
  # Count only this test's sessions: set aside any others, restore them after.
  old <- as.list(.registry, all.names = TRUE)
  rm(list = names(old), envir = .registry)
  withr::defer({
    rm(list = ls(.registry, all.names = TRUE), envir = .registry)
    list2env(old, envir = .registry)
  })

  expect_identical(spigot_broadcast("e", 1), 0L)
  a <- local_session()
  b <- local_session()
  expect_identical(spigot_broadcast("e", 1), 2L)
  b$sendCustomMessage <- function(type, message) stop("gone")
  expect_identical(spigot_broadcast("e", 1), 1L)
  expect_invisible(spigot_broadcast("e", 1))
})

test_that("spigot_broadcast() checks the event name", {
  expect_error(spigot_broadcast("", 1), "event")
  expect_error(spigot_broadcast(NULL, 1), "event")
})

test_that("spigot_broadcast(except =) skips the given sessions", {
  a <- local_session()
  b <- local_session()
  c <- local_session()
  base <- spigot_broadcast("e", 0)

  expect_identical(spigot_broadcast("e", 1, except = a), base - 1L)
  expect_length(events(a), 1)
  expect_length(events(b), 2)
  expect_length(events(c), 2)

  expect_identical(spigot_broadcast("e", 2, except = list(a, c)), base - 2L)
  expect_length(events(a), 1)
  expect_length(events(b), 3)
  expect_length(events(c), 2)

  # NULL (an endpoint without a session) skips nobody.
  expect_identical(spigot_broadcast("e", 3, except = NULL), base)
  expect_length(events(a), 2)
})

test_that("except = matches by identity, not by token text", {
  a <- local_session()
  lookalike <- fake_session(a$token)
  spigot_broadcast("e", 1, except = lookalike)
  expect_length(events(a), 1)
})

test_that("except = accepts a module's session and skips its root session", {
  a <- local_session()
  b <- local_session()
  spigot_broadcast("e", 1, except = fake_module_session(a))
  expect_length(events(a), 0)
  expect_length(events(b), 1)
})

test_that("spigot_broadcast(except =) rejects what is not a session", {
  local_session()
  expect_error(spigot_broadcast("e", 1, except = "abc"), "except")
  expect_error(spigot_broadcast("e", 1, except = list(fake_session(), 1)), "except")
})

test_that("spigot_broadcast(filter =) sends only where it returns TRUE", {
  red <- local_session()
  red$userData$room <- "red"
  blue <- local_session()
  blue$userData$room <- "blue"
  none <- local_session()

  seen <- list()
  n <- spigot_broadcast("e", 1, filter = function(session) {
    seen[[length(seen) + 1L]] <<- session
    identical(session$userData$room, "red")
  })
  expect_identical(n, 1L)
  expect_length(events(red), 1)
  expect_length(events(blue), 0)
  expect_length(events(none), 0)
  expect_true(any(vapply(seen, identical, logical(1), blue)))
})

test_that("filter = and except = combine", {
  a <- local_session()
  b <- local_session()
  a$userData$room <- b$userData$room <- "r"
  n <- spigot_broadcast("e", 1, except = a,
                        filter = function(s) identical(s$userData$room, "r"))
  expect_identical(n, 1L)
  expect_length(events(a), 0)
  expect_length(events(b), 1)
})

test_that("a failing or non-logical filter errors before anything is sent", {
  a <- local_session()
  b <- local_session()
  first <- TRUE
  boom <- function(s) {
    if (first) { first <<- FALSE; return(TRUE) }
    stop("filter bug")
  }
  expect_error(spigot_broadcast("e", 1, filter = boom), "filter bug")
  for (bad in list(function(s) NA, function(s) "yes", function(s) c(TRUE, TRUE),
                   function(s) NULL)) {
    expect_error(spigot_broadcast("e", 1, filter = bad), "TRUE or FALSE")
  }
  expect_length(events(a), 0)
  expect_length(events(b), 0)
  expect_error(spigot_broadcast("e", 1, filter = "room"), "filter")
})

test_that("filter = is not called for closed sessions", {
  a <- local_session()
  closed <- local_session()
  closed$isClosed <- function() TRUE
  calls <- 0L
  spigot_broadcast("e", 1, filter = function(s) {
    if (identical(s, closed)) calls <<- calls + 1L
    TRUE
  })
  expect_identical(calls, 0L)
  expect_length(events(a), 1)
})

test_that("prune_session() removes only that session", {
  a <- local_session()
  b <- local_session()
  prune_session(a)
  expect_null(lookup_session(a$token))
  expect_identical(lookup_session(b$token), b)
  expect_no_error(prune_session(a))
})

# ---- unit: payload shapes -------------------------------------------------------

test_that("push payloads use spigot_json() shapes", {
  s <- fake_session()
  json <- function(x) {
    spigot_emit(s, "e", x)
    sent <- s$sent()
    sent[[length(sent)]]$message$json
  }
  expect_identical(json(list(a = list(b = list(c = 1:2)))), '{"a":{"b":{"c":[1,2]}}}')
  expect_identical(json(I(1)), "[1]")
  expect_identical(json(list(one = I("x"))), '{"one":["x"]}')
  expect_identical(json(NA), "null")
  expect_identical(json(character(0)), "[]")
  expect_identical(json(data.frame(a = 1:2, b = c("x", NA))),
                   '[{"a":1,"b":"x"},{"a":2,"b":null}]')
  expect_identical(json(list(k = "v", n = 2)), '{"k":"v","n":2}')
  expect_identical(json(list(s = "Größe – ✓")), '{"s":"Größe – ✓"}')
})

# ---- integration: over Shiny's websocket, no browser ----------------------------

test_that("an endpoint's emit reaches only the calling session's socket", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "push"))
  me <- open_session(srv$url)
  other <- open_session(srv$url)

  r <- hit(paste0(srv$url, "/api/ping-me"), "POST", json = list(),
           headers = list(`X-Spigot-Session` = me$token))
  expect_identical(httr2::resp_status(r), 200L)
  got <- me$custom("spigot:event")
  expect_length(got, 1)
  expect_identical(got[[1]]$event, "ping")
  expect_identical(jsonlite::fromJSON(got[[1]]$json),
                   list(to = "me", from = me$token))
  expect_length(other$custom("spigot:event"), 0)
})

test_that("an endpoint's broadcast reaches every session's socket", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "push"))
  a <- open_session(srv$url)
  b <- open_session(srv$url)
  gone <- open_session(srv$url)
  gone$close()

  r <- hit(paste0(srv$url, "/api/ping-all"), "POST", json = list(),
           headers = list(`X-Spigot-Session` = a$token))
  expect_identical(httr2::resp_body_json(r)$sent, 2L)
  for (s in list(a, b)) {
    got <- s$custom("spigot:event")
    expect_length(got, 1)
    expect_identical(jsonlite::fromJSON(got[[1]]$json), list(to = "all", from = a$token))
  }
})

test_that("an endpoint can broadcast to every session except the caller", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "push"))
  me <- open_session(srv$url)
  other <- open_session(srv$url)

  r <- hit(paste0(srv$url, "/api/ping-others"), "POST", json = list(),
           headers = list(`X-Spigot-Session` = me$token))
  expect_identical(httr2::resp_body_json(r)$sent, 1L)
  expect_length(me$custom("spigot:event"), 0)
  got <- other$custom("spigot:event")
  expect_length(got, 1)
  expect_identical(jsonlite::fromJSON(got[[1]]$json), list(to = "others", from = me$token))
})

test_that("an endpoint can broadcast to the sessions a filter picks", {
  skip_on_cran()
  srv <- start_app(test_path("apps", "push"))
  a <- open_session(srv$url)
  b <- open_session(srv$url)
  c <- open_session(srv$url)
  join <- function(s, room) {
    hit(paste0(srv$url, "/api/join"), "POST", json = list(room = room),
        headers = list(`X-Spigot-Session` = s$token))
  }
  join(a, "red")
  join(b, "red")
  join(c, "blue")

  r <- hit(paste0(srv$url, "/api/say"), "POST", json = list(text = "hi"),
           headers = list(`X-Spigot-Session` = a$token))
  expect_identical(httr2::resp_body_json(r)$sent, 2L)
  for (s in list(a, b)) {
    got <- s$custom("spigot:event")
    expect_length(got, 1)
    expect_identical(jsonlite::fromJSON(got[[1]]$json), list(room = "red", text = "hi"))
  }
  expect_length(c$custom("spigot:event"), 0)
})

# ---- e2e: Chrome ----------------------------------------------------------------

# Record every `event` the tab receives in window.__got[event].
listen <- function(tab, event) {
  js(tab, sprintf("
    window.__got = window.__got || {};
    window.__got[%1$s] = [];
    spigot.on(%1$s, function (data, name) { window.__got[%1$s].push({data: data, name: name}); });
    true", jsonlite::toJSON(event, auto_unbox = TRUE)))
}

got <- function(tab, event, wait = 0) {
  if (wait > 0) Sys.sleep(wait)
  js(tab, sprintf("window.__got[%s]", jsonlite::toJSON(event, auto_unbox = TRUE)))
}

# Poll until the tab has received `n` of `event`; returns them.
await_got <- function(tab, event, n = 1, timeout = 5) {
  deadline <- Sys.time() + timeout
  repeat {
    x <- got(tab, event)
    if (length(x) >= n || Sys.time() > deadline) return(x)
    Sys.sleep(0.05)
  }
}

push_tabs <- function(env = parent.frame()) {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "push"), env = env)
  list(srv = srv, a = new_tab(srv$url, env = env), b = new_tab(srv$url, env = env))
}

test_that("spigot_emit() from an endpoint fires only the calling tab's listener", {
  x <- push_tabs()
  listen(x$a, "ping")
  listen(x$b, "ping")
  js(x$a, 'spigot.post("ping-me")')
  a <- await_got(x$a, "ping")
  expect_length(a, 1)
  expect_identical(a[[1]]$name, "ping")
  expect_identical(a[[1]]$data, list(to = "me", from = js(x$a, "spigot.sessionId")))
  expect_length(got(x$a, "ping", wait = 0.5), 1)
  expect_length(got(x$b, "ping"), 0)
})

test_that("spigot_broadcast() from an endpoint fires every tab's listener", {
  x <- push_tabs()
  listen(x$a, "ping")
  listen(x$b, "ping")
  js(x$b, 'spigot.post("ping-all")')
  from <- js(x$b, "spigot.sessionId")
  for (tab in list(x$a, x$b)) {
    g <- await_got(tab, "ping")
    expect_length(g, 1)
    expect_identical(g[[1]]$data, list(to = "all", from = from))
  }
})

test_that("several listeners fire; spigot.off() and the returned function remove them", {
  x <- push_tabs()
  js(x$a, "
    window.__calls = [];
    window.__one = function (d) { window.__calls.push('one'); };
    window.__stop = spigot.on('ping', window.__one);
    spigot.on('ping', function (d) { window.__calls.push('two'); });
    spigot.on('other', function (d) { window.__calls.push('other'); });
    true")
  expect_identical(js(x$a, "typeof window.__stop"), "function")
  calls <- function() unlist(js(x$a, "window.__calls"))

  js(x$a, 'spigot.post("ping-me")')
  expect_true(eventually(function() length(calls()) == 2, timeout = 5))
  expect_setequal(calls(), c("one", "two"))

  js(x$a, "window.__calls = []; spigot.off('ping', window.__one); true")
  js(x$a, 'spigot.post("ping-me")')
  expect_true(eventually(function() length(calls()) >= 1, timeout = 5))
  Sys.sleep(0.3)
  expect_identical(calls(), "two")

  js(x$a, "window.__calls = []; spigot.off('ping'); true")
  js(x$a, 'spigot.post("ping-me")')
  Sys.sleep(0.5)
  expect_null(calls())

  js(x$a, "window.__calls = []; spigot.on('ping', window.__one); window.__stop(); true")
  js(x$a, 'spigot.post("ping-me")')
  Sys.sleep(0.5)
  expect_null(calls())
})

test_that("adding the same listener twice registers it once", {
  x <- push_tabs()
  js(x$a, "
    window.__n = 0;
    window.__f = function () { window.__n++; };
    spigot.on('ping', window.__f);
    spigot.on('ping', window.__f);
    true")
  js(x$a, 'spigot.post("ping-me")')
  expect_true(eventually(function() js(x$a, "window.__n") >= 1, timeout = 5))
  Sys.sleep(0.3)
  expect_identical(js(x$a, "window.__n"), 1L)
})

test_that("a listener that throws does not stop the others", {
  x <- push_tabs()
  js(x$a, "
    window.__errors = [];
    window.addEventListener('error', function (e) { window.__errors.push(e.message); });
    spigot.on('ping', function () { throw new Error('bad listener'); });
    window.__ran = false;
    spigot.on('ping', function () { window.__ran = true; });
    true")
  js(x$a, 'spigot.post("ping-me")')
  expect_true(eventually(function() isTRUE(js(x$a, "window.__ran")), timeout = 5))
  # The error is still reported, the way the DOM reports a listener's error.
  expect_true(eventually(function() length(js(x$a, "window.__errors")) == 1, timeout = 2))
  expect_match(js(x$a, "window.__errors[0]"), "bad listener")
})

test_that("a listener may remove itself while the event is dispatched", {
  x <- push_tabs()
  js(x$a, "
    window.__calls = [];
    window.__self = function () { window.__calls.push('self'); spigot.off('ping', window.__self); };
    spigot.on('ping', window.__self);
    spigot.on('ping', function () { window.__calls.push('next'); });
    true")
  js(x$a, 'spigot.post("ping-me")')
  expect_true(eventually(function() length(js(x$a, "window.__calls")) == 2, timeout = 5))
  expect_identical(unlist(js(x$a, "window.__calls")), c("self", "next"))
})

test_that("spigot.on() rejects a listener that is not a function", {
  x <- push_tabs()
  expect_error(js(x$a, "spigot.on('ping', 'nope')"), "function")
  expect_error(js(x$a, "spigot.on('', function () {})"), "event")
})

test_that("payload shapes survive the trip to the browser", {
  x <- push_tabs()
  listen(x$a, "shapes")
  js(x$a, 'spigot.post("shapes")')
  d <- await_got(x$a, "shapes")[[1]]$data
  expect_true(js(x$a, "Array.isArray(window.__got.shapes[0].data.one) &&
                       window.__got.shapes[0].data.one.length === 1"))
  expect_identical(js(x$a, "typeof window.__got.shapes[0].data.scalar"), "number")
  expect_identical(js(x$a, "window.__got.shapes[0].data.na === null"), TRUE)
  expect_identical(js(x$a, "JSON.stringify(window.__got.shapes[0].data.empty)"), "[]")
  expect_identical(d$rows, list(list(a = 1L, b = "x"), list(a = 2L, b = NULL)))
  expect_identical(d$obj, list(k = "v", nested = list(deep = list("d"))))
})
