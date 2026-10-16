# Reactive bridge: spigot_trigger() sets a Shiny input from an endpoint (PLAN M6).

# The spigot:set-input messages a fake session was sent.
set_inputs <- function(s) {
  sent <- Filter(function(m) identical(m$type, "spigot:set-input"), s$sent())
  lapply(sent, `[[`, "message")
}

# What Shiny does with the value spigot.js sends back:
# Shiny.setInputValue("<name>:spigot.ref", id) reaches the server as
# {"<name>:spigot.ref": id}, and Shiny runs it through the input handler.
echo <- function(s, msg) {
  data <- stats::setNames(list(msg$id), paste0(msg$name, ":spigot.ref"))
  shiny:::applyInputHandlers(data, s)
}

# ---- unit: spigot_trigger() -----------------------------------------------------

test_that("spigot_trigger() sends one spigot:set-input message with the name and an id", {
  s <- fake_session()
  spigot_trigger(s, "cart", list(n = 2))
  sent <- s$sent()
  expect_length(sent, 1)
  expect_identical(sent[[1]]$type, "spigot:set-input")
  expect_named(sent[[1]]$message, c("name", "id"))
  expect_identical(sent[[1]]$message$name, "cart")
  id <- sent[[1]]$message$id
  expect_true(is.character(id) && length(id) == 1 && nzchar(id))
})

test_that("the value comes back from the input handler unchanged", {
  s <- fake_session()
  values <- list(
    list(n = 2),
    I(1),
    NA,
    NULL,
    data.frame(a = 1:2, b = c("x", NA)),
    factor(c("lo", "hi")),
    as.Date("2026-10-16"),
    list(list(1, "a"), list(2, "b")),
    new.env(),
    function(x) x + 1
  )
  for (v in values) {
    spigot_trigger(s, "cart", v)
    msg <- set_inputs(s)[[length(set_inputs(s))]]
    got <- echo(s, msg)
    expect_named(got, "cart")
    expect_identical(got[["cart"]], v)
  }
})

test_that("each trigger gets its own id, and an id resolves once", {
  s <- fake_session()
  spigot_trigger(s, "cart", 1)
  spigot_trigger(s, "cart", 1)
  msgs <- set_inputs(s)
  expect_false(identical(msgs[[1]]$id, msgs[[2]]$id))
  expect_identical(echo(s, msgs[[2]])$cart, 1)
  expect_identical(echo(s, msgs[[1]])$cart, 1)
  # Resolved values are dropped, so nothing is kept for the session's life.
  expect_null(echo(s, msgs[[1]])$cart)
  expect_length(ls(trigger_store(s), all.names = TRUE), 0)
})

test_that("an unknown or malformed id resolves to NULL without an error", {
  s <- fake_session()
  for (bad in list("nope", 1L, NULL, list("a"), c("a", "b"), NA_character_)) {
    expect_null(echo(s, list(name = "cart", id = bad))$cart)
  }
})

test_that("an id resolves only in the session that triggered it", {
  a <- fake_session()
  b <- fake_session()
  spigot_trigger(a, "cart", "secret")
  msg <- set_inputs(a)[[1]]
  expect_null(echo(b, msg)$cart)
  expect_identical(echo(a, msg)$cart, "secret")
})

test_that("spigot_trigger() returns TRUE invisibly", {
  s <- fake_session()
  expect_invisible(spigot_trigger(s, "cart", 1))
  expect_true(spigot_trigger(s, "cart", 1))
})

test_that("spigot_trigger() checks the input name", {
  s <- fake_session()
  for (bad in list(NULL, NA_character_, "", c("a", "b"), 1, "1abc", "_x", "a b",
                   "a:b", "cart:spigot.ref", "é")) {
    expect_error(spigot_trigger(s, bad, 1), "name")
  }
  for (ok in c("a", "cart", "Cart_2", "a.b", "a-b", "x9")) {
    expect_no_error(spigot_trigger(s, ok, 1))
  }
  expect_identical(vapply(set_inputs(s), `[[`, "", "name"),
                   c("a", "cart", "Cart_2", "a.b", "a-b", "x9"))
})

test_that("spigot_trigger() without a session is an error", {
  expect_error(spigot_trigger(NULL, "cart", 1), "session")
  expect_error(spigot_trigger(list(token = "x"), "cart", 1), "session")
})

test_that("a module's session namespaces the name and stores on its root", {
  root <- fake_session()
  mod <- fake_module_session(root)
  spigot_trigger(mod, "cart", 3)
  msg <- set_inputs(root)[[1]]
  expect_identical(msg$name, "mod-cart")
  # Shiny calls the input handler with the root session.
  expect_identical(echo(root, msg)[["mod-cart"]], 3)
})

test_that("spigot_trigger() does not touch the registry or userData's visible names", {
  s <- fake_session()
  spigot_trigger(s, "cart", 1)
  expect_null(lookup_session(s$token))
  expect_identical(ls(s$userData), character())
})

test_that("the spigot.ref input handler is registered when spigot loads", {
  expect_true(shiny:::inputHandlers$containsKey("spigot.ref"))
})

# ---- e2e: Chrome ----------------------------------------------------------------

# Record every `event` the tab receives in window.__got[event].
listen_for <- function(tab, event) {
  js(tab, sprintf("
    window.__got = window.__got || {};
    window.__got[%1$s] = [];
    spigot.on(%1$s, function (data) { window.__got[%1$s].push(data); });
    true", jsonlite::toJSON(event, auto_unbox = TRUE)))
}

received <- function(tab, event) {
  js(tab, sprintf("window.__got[%s]", jsonlite::toJSON(event, auto_unbox = TRUE)))
}

trigger_tab <- function(env = parent.frame()) {
  skip_if_no_chrome()
  srv <- start_app(test_path("apps", "trigger"), env = env)
  new_tab(srv$url, env = env)
}

test_that("an endpoint's trigger fires the observer once with the value", {
  tab <- trigger_tab()
  listen_for(tab, "cart:observed")
  js(tab, 'spigot.post("cart/add", {value: {n: 2, sku: "RKS0420"}})')
  expect_true(eventually(function() length(received(tab, "cart:observed")) >= 1, timeout = 5))
  Sys.sleep(0.5)
  got <- received(tab, "cart:observed")
  expect_length(got, 1)
  expect_identical(got[[1]], list(n = 2L, sku = "RKS0420"))
})

test_that("rapid triggers with the same value each fire the observer", {
  tab <- trigger_tab()
  listen_for(tab, "cart:observed")
  js(tab, '
    var posts = [];
    for (var i = 0; i < 5; i++) posts.push(spigot.post("cart/add", {value: "same"}));
    Promise.all(posts).then(function () { return true; })')
  expect_true(eventually(function() length(received(tab, "cart:observed")) >= 5, timeout = 5))
  Sys.sleep(0.5)
  got <- received(tab, "cart:observed")
  expect_length(got, 5)
  expect_identical(unique(unlist(got)), "same")
})

test_that("trigger latency stays under the M0 bound", {
  tab <- trigger_tab()
  # fetch start -> observer's event, sequentially, after warm-up.
  # Bound: 5x the M0 step 5 p95 (DECISIONS.md).
  ms <- js(tab, "
    (async function () {
      var times = [];
      for (var i = 0; i < 25; i++) {
        var t0 = performance.now();
        var seen = new Promise(function (resolve) {
          var stop = spigot.on('cart:observed', function () { stop(); resolve(); });
        });
        await spigot.post('cart/add', {value: i});
        await seen;
        if (i >= 5) times.push(performance.now() - t0);
      }
      return times;
    })()", timeout = 30)
  ms <- unlist(ms)
  expect_length(ms, 20)
  expect_lt(stats::median(ms), 215)
})

test_that("values JSON cannot carry reach input$ unchanged", {
  tab <- trigger_tab()
  listen_for(tab, "shapes:observed")
  js(tab, 'spigot.post("shapes")')
  expect_true(eventually(function() length(received(tab, "shapes:observed")) >= 1, timeout = 5))
  expect_identical(received(tab, "shapes:observed"), list(list(identical = TRUE)))
})
