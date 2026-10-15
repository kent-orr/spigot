# PLAN: `spigot` — plumber endpoints inside a Shiny app

> Working name. Check CRAN/GitHub availability before first commit.
>
> Revision 2 (2026-10-15): milestones expanded into step-by-step instructions.
> Assumptions about Shiny/plumber internals were verified against
> shiny 1.14.0 (installed) and plumber `main` on GitHub (CRAN 1.3.3). See §4.0.
>
> M0 complete (2026-10-15): all spikes recorded in DECISIONS.md; stale facts above corrected.
>
> M1 complete (2026-10-15): F16–F18 added; `spigot_api()` signature changed (DECISIONS.md).
>
> M2 complete (2026-10-15): F19–F20 added; `max_request_size` now defaults to `NULL` (DECISIONS.md).

## 1. Goal

Build Shiny "sites" where:

- **Frontend** is hand-written HTML/JS (whisker templates + `fetch`/async), not `fluidPage`.
- **Backend** is R: plumber 1.x routes mounted *inside* the Shiny process, same origin, same port.
- The API exists **only for the app's own pages**. No external consumers, no public API.
- Shiny still provides: hosting (Shiny Server / Connect / `runApp`), per-tab session state, and a server→client push channel.

### Non-goals

- Public/third-party API, API keys, versioning, rate limiting.
- Replacing Shiny outputs/reactivity for people who want them (it stays available, opt-in).
- Horizontal scaling beyond what Shiny already supports.
- A JS build toolchain. Users may bring Vite/esbuild; the package only serves the output.

## 2. Mental model (how reactivity fits)

```
Browser tab ──HTTP fetch──▶ /api/*  ──▶ plumber router ─┐
     ▲                                                  │ same R process,
     │                                                  │ same memory
     └──websocket (Shiny session)◀── observers/push ◀───┘
```

| Channel | Direction | Use for | Reactive? |
|---|---|---|---|
| HTTP (`spigot.get/post`) | client → server → client | Queries, commands, form submits, data loads | No. Plain request/response |
| Push (`spigot.on`) | server → client | Live updates, progress, server-initiated events | Driven by observers |
| Bridge (`spigot_trigger`) | HTTP → reactive graph | When an API call should invalidate reactives | Yes, opt-in |

Rules of thumb:

- **Most apps need only HTTP.** Shiny is just the host plus the session.
- Endpoints that are **session-bound** (see §4.2) can read session state with `isolate()` and push to that tab.
- Reactivity is an **optional layer** for live views. It is not required for anything.

## 3. User-facing API (target)

### R

```r
spigot_app(
  pages,                 # named list: path -> spigot_page(), or a single page for "/"
  server = NULL,         # optional Shiny server function (reactivity, push)
  api,                   # plumber router or path to plumber file(s)
  prefix = "/api",
  require_session = TRUE,# reject API calls without a live session token
  max_request_size = NULL        # bytes -> options(shiny.maxRequestSize); NULL leaves it alone
)

spigot_api(file = NULL, envir = parent.frame())  # plumber::pr() with spigot_json() as default serializer
spigot_page(template, data = list(), partials = list(), cache = FALSE)
spigot_session(req)                        # inside an endpoint: bound ShinySession or NULL
spigot_emit(session, event, data)          # push to one tab
spigot_broadcast(event, data)              # push to all live sessions
spigot_trigger(session, name, value)       # set a reactive input from an endpoint
spigot_dependency()                        # htmltools dependency for spigot.js
```

### Endpoint example

```r
#* @post /cart/add
function(req, sku, qty) {
  s <- spigot::spigot_session(req)
  cart <- add_to_cart(s$userData$cart_id, sku, as.integer(qty))
  spigot::spigot_emit(s, "cart:changed", cart)   # optional live update
  cart
}
```

### JS (`spigot.js`)

```js
await spigot.ready;                                // resolves on shiny:sessioninitialized
const cart = await spigot.post("cart/add", {sku, qty: 1});
const rows = await spigot.get("forecast", {sku: "RKS0420", h: 12});
spigot.on("cart:changed", renderCart);
```

- Relative URLs only (works under Shiny Server/Connect subpaths).
- Sends the session token header automatically.
- Throws `SpigotError {status, message, body}` on non-2xx.
- JSON in and out by default; raw `fetch` is still available for files and streams.

## 4. Architecture

### 4.0 Verified facts (2026-10-15, shiny 1.14.0, plumber main)

These were read from source, not assumed. Re-verify when bumping either dependency.

| # | Fact | Consequence for design |
|---|---|---|
| F1 | `shinyApp()` returns `structure(list(httpHandler, serverFuncSource, onStart, options, appOptions), class = "shiny.appobj")`. | Wrapping `app$httpHandler` and `app$serverFuncSource` is the whole mount. |
| F2 | Shiny's HTTP chain order is `sessionHandler` → app `httpHandler` → `www/` static → `resourcePathHandler` → `reactLogHandler`. | `/session/<hex>/…` is reserved by Shiny. `prefix` must not collide with a resource path or `www/` folder. |
| F3 | `uiHttpHandler()` only answers `GET` (unless `attr(ui, "http_methods_supported")` is set). | Our wrapper must intercept `/api/*` *before* delegating, so POST/PUT/DELETE never reach the UI handler. |
| F4 | `HandlerManager$.httpServer` runs the handler's return through `promises::hybrid_chain()`. A promise is awaited; its value must be an `httpResponse` (or raw Rook list). | Returning `pr$call(req)` (possibly a promise) chained with `then(rook_to_httpResponse)` just works. |
| F5 | Shiny's httpuv `onHeaders` rejects bodies over `getOption("shiny.maxRequestSize", 5 MB)` with 413 **before any handler runs**. plumber's `plumber.maxRequestSize` is only enforced inside `pr$run()`. | `spigot_app(max_request_size=)` sets `shiny.maxRequestSize`. Do not rely on plumber's option. |
| F6 | Errors thrown by an app `httpHandler` become Shiny's HTML 500 page (`template/error.html`), subject to `shiny.sanitize.errors`. plumber catches endpoint errors itself and returns JSON 500. | Mount code must `tryCatch` its *own* failures and return JSON 500 so API clients never receive HTML. |
| F7 | `session$token` is `createUniqueId(16)` (hex). `ShinySession$initialize` sends `config = list(workerId, sessionId = token, user)`. JS exposes it as `Shiny.shinyapp.config.sessionId`, set just before `shiny:sessioninitialized` fires (not at `shiny:connected`). | Token header value is exactly `session$token`. Validate with `^[0-9a-f]{16,}$` before registry lookup. |
| F8 | `ShinySession$sendCustomMessage(type, message)` and `onSessionEnded(cb)` are public. `session$userData` is a public env. | No internals needed for push, registry cleanup, or per-tab state. |
| F9 | `uiHttpHandler`: if `ui(req)` returns an `httpResponse`, it is passed through untouched; if it returns an `html_document` (from `htmlTemplate(..., document_ = TRUE)`), `renderPage()` injects jQuery + shiny.js + attached deps without wrapping it. | Pages can be full documents authored by the user and still get Shiny deps without touching internals (§4.3). |
| F10 | `shinyApp(uiPattern = ".*")` is wrapped as `^.*$`. | Multi-page routing via `ui = function(req)` is supported publicly. |
| F11 | `maybeInjectAutoreload()` and `shiny.http.response.filter` only act on `httpResponse` objects with `text/html` content. | Converting to `httpResponse` keeps devmode features working; JSON responses are untouched. |
| F12 | plumber `Plumber$call(req)` sets `req$pr`, `req$.internal`, `req$args`, builds a `PlumberResponse`, then `serve()` → `res$toResponse()` = `list(status, headers, body)`. Body is `NULL` for 1xx/204/304. Promises in endpoints/filters/hooks are supported since plumber 1.0.0. | `req` must be the httpuv environment (plumber mutates it). Response conversion is a 10-line function. |
| F13 | plumber's default `bodyFilter` does `req$bodyRaw <- req$rook.input$read()` once. | The mount must **not** read `rook.input` before `pr$call()`. If it ever must, call `rook.input$rewind()` after. |
| F14 | `plumber.trailingSlash` defaults to `FALSE`; `plumber.methodNotAllowed` defaults to `TRUE` (405 when path exists under another verb). | After stripping the prefix, map `""` to `"/"`. Expect 405, not 404, for wrong-verb tests. |
| F15 | Shiny's `sendCustomMessage` serialises with Shiny's `toJSON` settings (`auto_unbox = TRUE`). | Pre-serialise push payloads with our own `jsonlite::toJSON()` config and send a single string (§4.4). |
| F16 | `shinyAppDir()` serves `www/` as an httpuv static path at `/`; httpuv answers non-GET requests under it with 400 before R runs. Static paths come from the *outer* appobj. | `mount_app()` adds `excludeStaticPath()` for the prefix via `getShinyOption("server")$setStaticPath()` on the first loop tick after `onStart` (DECISIONS.md M1). |
| F17 | plumber copies the router's default serializer into each endpoint at creation; file endpoints without `@serializer` resolve it per request. | `spigot_api()` with no file returns a router that already has the serializer; a `Plumber` passed in is left unchanged. |
| F18 | httpuv sets both `CONTENT_TYPE` and `HTTP_CONTENT_TYPE` (plumber reads the latter), plus `HEADERS`. | `fake_req()` mirrors this. |
| F19 | Shiny's `onHeaders` reads `shiny.maxRequestSize` per request; a body without `Content-Length` but with `Transfer-Encoding` counts as `Inf`. | Setting the option in `onStart` works; chunked uploads always get 413 under a finite limit. |
| F20 | `argsForServerFunc()` passes `session` (and `clientData`) only when named in the server's formals. | `wrap_server()` always takes `session` and mirrors this rule for the user's function. |

Environment on this dev machine: R 4.5.2, shiny 1.14.0, whisker 0.4.1, htmltools 0.5.9,
jsonlite 2.0.0, promises 1.5.0, httr2 1.3.0, callr 3.8.0, testthat 3.3.2, later 1.4.8,
future 1.70.0, httpuv 1.6.17, plumber 1.3.3, chromote 0.5.1 + Chrome for Testing 155
(headless shell, run with `--no-sandbox`). mirai not installed. See DECISIONS.md step 0.

### 4.1 Mounting

- Replace `app$httpHandler` with a wrapper. Requests matching `^{prefix}(/|$)` have the prefix moved from `PATH_INFO` to `SCRIPT_NAME` (same trick as Shiny's own `routeHandler()`), then go to `pr$call(req)`. The result (value or promise) is chained with `rook_to_httpResponse()` (F4, F12).
- Everything else returns `NULL` from the wrapper → falls through to the original handler and Shiny's static/resource handlers (F2).
- The prefix is excluded from httpuv static serving at startup (F16), or API POSTs in an app dir with `www/` get 400.
- **Risk:** depends on the `shiny.appobj` structure (F1). Mitigate by: asserting the structure at `spigot_app()` time and failing loudly; pinning `shiny (>= 1.14.0)` initially and walking the lower bound back in CI; keeping `mount.R` the only file touching it.

### 4.2 Session binding

- `spigot_app()` wraps the user's `server` function. On session start it registers `session$token → session` in a package-level `new.env()` registry and removes the entry in `session$onSessionEnded()` (F8).
- JS reads `Shiny.shinyapp.config.sessionId` (F7) and sends it as `X-Spigot-Session`.
- The mount handler validates the header (hex), looks up the session, and sets `req$spigot_session` before `pr$call()`.
- `require_session = TRUE`: missing or unknown token → 401 JSON. Only live pages of this app can call the API.
- Cross-origin guard: if `Origin` (or `Referer` when `Origin` absent) is present and its host:port differs from `Host` → 403 JSON. Same-origin `fetch` always sends `Origin` on POST, and sends nothing on same-origin GET, so "absent" is allowed.
- Cross-origin guard also accepts `X-Forwarded-Host` (proxies that rewrite `Host`) and normalises default ports (DECISIONS.md M2).
- Body size: forward `max_request_size` to `options(shiny.maxRequestSize)` (F5, F19). Shiny answers 413 itself.

### 4.3 Pages and templates (whisker)

- `spigot_page()` renders a whisker template with `data`/`partials` into a complete HTML string.
- **Delimiter conflict:** `htmlTemplate()` and whisker both use `{{ }}`. If whisker output were passed through `htmlTemplate(text_ = …)`, user *data* containing `{{ }}` would be evaluated as R. That is a code-injection hole, so option B from revision 1 is **rejected**.
- **Chosen approach (verify in M0):** render with whisker; split the result once at the first `</head>`; feed the two halves as `HTML()` values into a fixed internal template:

  ```r
  htmltools::htmlTemplate(
    text_ = "{{ head }}{{ headContent() }}</head>{{ rest }}",
    head = HTML(head_part), rest = HTML(rest_part), document_ = TRUE
  )
  ```

  `HTML()` values are never re-templated. Returning the `html_document` lets Shiny inject jQuery, shiny.js and `spigot_dependency()` publicly (F9). No string surgery on dependency HTML, no internals.
- Templates without `</head>` → error at `spigot_page()` creation time with a clear message.
- Multi-page: `ui` becomes a `function(req)` that routes on `req$PATH_INFO`, with `shinyApp(uiPattern = ".*")` (F10). Unknown paths → a 404 `httpResponse` (F9). Trailing slashes are normalised (`/about/` == `/about`).
- Render timing: per request by default. `cache = TRUE` renders once at first request and memoises the `html_document` (safe because `data` is static).

### 4.4 Push

- One custom message type, `spigot:event`, with payload `list(event = "<name>", json = "<pre-serialised string>")` (F15). JS does `JSON.parse(msg.json)` and dispatches to `spigot.on` listeners.
- Serialiser config lives in one function, `spigot_json()`: `jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA, dataframe = "rows")`. The same function serialises nothing else. Length-1 arrays are preserved with `I()`.
- `spigot_broadcast()` iterates over the registry. Dead sessions are skipped and pruned.

### 4.5 Reactive bridge (`spigot_trigger`)

Problem: setting a `reactiveVal` from an HTTP handler happens outside Shiny's flush cycle, so outputs may not update until the next websocket event.

Options (spike in M0, pick one):

1. **Round-trip** (no internals): the server sends custom message `spigot:set-input` `{name, value}`, and JS calls `Shiny.setInputValue(name, value, {priority: "event"})`. This guarantees a normal flush and costs one extra websocket hop. `priority: "event"` is confirmed present in shiny.min.js 1.14.0.
2. **Direct + scheduled flush**: run `withReactiveDomain(session, rv(value))` followed by `later::later(<flush>)`. This needs an internal Shiny function, so it is rejected unless option 1 proves too slow.

Default to option 1. Server code then just uses `input$<name>` as usual.

### 4.6 Concurrency

- One R thread. A synchronous endpoint blocks every session in the process.
- Document `promises::future_promise()` / `mirai` for anything over ~100 ms.
- Promise results flow through the mount handler unchanged (F4, F12).
- Expose `spigot_options(timeout = …)`. JS also enforces a client-side timeout via `AbortController`.

## 5. Package layout

```
spigot/
├── DESCRIPTION
├── NAMESPACE                 # generated by roxygen2; never hand-edited
├── DECISIONS.md              # outcome of each M0 spike, one dated entry per decision
├── R/
│   ├── app.R          # spigot_app(), page routing
│   ├── mount.R        # httpHandler wrapping (ONLY file touching shiny.appobj structure)
│   ├── rook.R         # rook ↔ httpResponse conversion, JSON error responses
│   ├── session.R      # registry, spigot_session(), emit/broadcast/trigger
│   ├── page.R         # spigot_page(), whisker + dependency injection
│   ├── api.R          # spigot_api()
│   ├── deps.R         # spigot_dependency()
│   ├── json.R         # spigot_json(): the single serializer config
│   └── utils.R
├── inst/
│   ├── js/spigot.js
│   └── examples/
│       ├── minimal/   # one page, one endpoint
│       ├── live/      # push + spigot_trigger
│       └── site/      # multi-page, partials, async endpoint
├── (spikes/)          # M0 only; deleted in M1 (see git history)
├── tests/testthat/
│   ├── helper-req.R       # fake_req(): Rook request environment with rook.input
│   ├── helper-server.R    # callr + httr2 harness, random port, readiness wait
│   ├── helper-chrome.R    # skip_if_no_chrome(), tab helpers
│   ├── test-json.R        # unit
│   ├── test-rook.R        # unit
│   ├── test-mount.R       # unit (fake req) + integration (live server)
│   ├── test-session.R     # unit (fake session) + integration
│   ├── test-page.R        # unit + integration
│   ├── test-client.R      # e2e (chromote)
│   ├── test-push.R        # e2e (chromote)
│   └── test-trigger.R     # e2e (chromote)
└── vignettes/
    ├── getting-started.Rmd
    └── reactivity.Rmd     # §2 expanded
```

**Imports:** shiny (>= 1.14.0), plumber (>= 1.0.0), whisker, htmltools, jsonlite, promises
**Suggests:** testthat (>= 3.0), httr2, callr, chromote, future, later, roxygen2, knitr, rmarkdown

**Conventions (from project rules):** test-first for every behaviour below; `.Rd` files are generated with `roxygen2` (`devtools::document()`), never edited by hand.

## 6. Milestones (test-first)

Each milestone follows the same loop:

1. Write the test file(s) listed. Run `devtools::test(filter = "<name>")` and confirm they **fail** for the right reason (missing function, not a typo).
2. Implement the smallest code that passes.
3. Run the whole suite, then `devtools::document()` and `devtools::check()` (`--no-manual` is fine until M7).
4. Commit with the milestone tag in the message, e.g. `M1: mount GET/POST through plumber`.

Shared test harness (write during M1, reuse everywhere):

- `fake_req(method = "GET", path = "/", query = "", body = NULL, headers = list())` → an environment shaped like httpuv's: `REQUEST_METHOD`, `PATH_INFO`, `SCRIPT_NAME = ""`, `QUERY_STRING` (with leading `?`), `HTTP_HOST = "127.0.0.1:1234"`, `CONTENT_TYPE` and `HTTP_CONTENT_TYPE`, `CONTENT_LENGTH` and `HTTP_CONTENT_LENGTH`, `HTTP_*` for each header, `HEADERS` (F18), and `rook.input` = an R6/list object with `read()`, `read_lines()`, `rewind()` over a raw vector. Lets most mount/session tests run with no server.
- `start_app(app_dir_or_expr)` → `callr::r_bg()` running `shiny::runApp(..., port = httpuv::randomPort(), launch.browser = FALSE)`; polls `httr2::request(url)` until 200 or 10 s; returns `list(url, proc)`; `withr::defer(proc$kill())` in the caller.
- `skip_if_no_chrome()` → `testthat::skip_if_not_installed("chromote")` plus `chromote::find_chrome()` is non-NULL (chromote ≥ 0.5 can also download one via `chromote::local_chrome_version()`; document that for CI).
- `new_tab(url)` → `chromote::ChromoteSession$new()`, navigate, wait for `window.Shiny && Shiny.shinyapp.config` via `Runtime.evaluate` polling.

### M0: Spikes (throwaway, `spikes/`)

Goal: turn every "verify" in §4 into a recorded decision. Nothing from `spikes/` ships.

**Step 0 — environment.**
- `install.packages(c("plumber", "chromote"))`. plumber on CRAN is 1.3.3, chromote 0.5.1.
- Install a browser for chromote: `chromote::local_chrome_version()` (downloads Chrome for Testing into the chromote cache) or a system Chromium. Record the chosen route in `DECISIONS.md` because CI will need it too.
- Confirm `chromote::find_chrome()` returns a path.

**Step 1 — mount reaches all verbs; `rook.input` behaviour** (`spikes/01-mount.R`).
- Build `pr <- plumber::pr()` with `GET /`, `POST /echo` (returns `req$body`), `PUT /x`, `DELETE /x`.
- Build `app <- shinyApp(ui = fluidPage(), server = function(...) {})`, then replace `app$httpHandler` with a wrapper that strips `/api` and calls `pr$call(req)` and converts the Rook list to `httpResponse` (prototype of `rook.R`).
- `runApp(app, port = 8765)` in a `callr::r_bg()`; from the parent use `httr2` to hit each verb; assert status 200 and that POST echoes a JSON body.
- Then add a second POST where the wrapper reads `req$rook.input$read()` *before* `pr$call()` without rewinding: confirm plumber sees an empty body. Add `rewind()` and confirm it recovers. Record: "never pre-read; if you must, rewind" (F13).
- Record also whether `req$PATH_INFO` is `""` or `"/"` after stripping `/api` exactly (F14).

**Step 2 — promise from `httpHandler` is awaited** (`spikes/02-promise.R`).
- Add endpoint `GET /slow` returning `promises::future_promise({ Sys.sleep(2); list(ok = TRUE) })` with `future::plan(multisession)`.
- Fire `/slow` and `/` concurrently from two `httr2` requests (or `curl::multi_run`). Assert `/` returns in < 500 ms while `/slow` takes ≥ 2 s. This proves both F4 and that the process is not blocked.

**Step 3 — session token on the JS side** (`spikes/03-token.R`).
- App with `server = function(input, output, session) { message("TOKEN ", session$token) }`.
- Open the page in chromote, evaluate `Shiny.shinyapp.config.sessionId`, compare with the logged token. Expect equality (F7).
- Also time how long after page load the field exists (needed for `spigot.ready` design): poll from `DOMContentLoaded` until defined, log ms.

**Step 4 — whisker page + Shiny deps** (`spikes/04-page.R`).
- Write a whisker template that is a full document with `<head>…</head>` and `{{title}}` / `{{#items}}` / `{{> footer}}` usage.
- Implement the §4.3 split-and-`htmlTemplate` approach as `ui <- function(req) …` returning the `html_document`.
- Open in chromote. Assert in the DOM: exactly one `script[src*="shiny"]`, exactly one jQuery, `Shiny.shinyapp` defined, and a `data = list(title = "{{ Sys.getenv('HOME') }}")` renders *literally* (no evaluation). That last assertion is the injection test that kills option B.
- Record the chosen approach and the exact head-split rule in `DECISIONS.md`.

**Step 5 — bridge latency** (`spikes/05-trigger.R`).
- Endpoint `POST /tick` that does `session$sendCustomMessage("spigot:set-input", list(name = "tick", value = Sys.time()))`. JS handler calls `Shiny.setInputValue("tick", v, {priority: "event"})`. Server has `observeEvent(input$tick, session$sendCustomMessage("pong", Sys.time()))`.
- From chromote, POST `/api/tick` 50 times and measure fetch-resolve → pong-received latency in the browser. Report median and p95.
- Decision rule: if p95 < 50 ms on localhost, option 1 is adopted and option 2 is closed.

**Exit:** `DECISIONS.md` has one dated entry per step (0–5) with the evidence (numbers, versions). `spikes/` is left in the tree until M1 is merged, then deleted.

### M1: Mount

**Tests first** (`test-json.R`, `test-rook.R`, `test-mount.R`, helpers):

1. `helper-req.R` with `fake_req()` as specified above. Test the helper itself: `rook.input$read()` returns the raw body, a second `read()` returns `raw(0)`, `rewind()` restores.
2. `test-json.R`: `spigot_json()` round-trips: scalar → unboxed; `I(1)` → `[1]`; `NA` → `null`; `NULL` → `null`; nested list; data frame → row objects; Date/POSIXct → ISO strings.
3. `test-rook.R`: `rook_to_httpResponse(list(status, headers, body))`:
   - `Content-Type` in plumber headers becomes `content_type`; it is removed from `headers`.
   - Missing content type → `application/octet-stream` for raw, `text/plain` for character.
   - Body `NULL` (204) → `content = ""`. Raw body passes through unchanged. Character body is UTF-8.
   - Other headers (e.g. `Set-Cookie`, `Cache-Control`) preserved; `X-Content-Type-Options: nosniff` added by `httpResponse`.
   - `json_error(status, message)` returns an `httpResponse` with `application/json` and `{"error": …}`.
4. `test-mount.R`, **unit** (fake req, no server). Build `h <- spigot_mount_handler(pr, prefix = "/api", fallback = function(req) NULL)` and assert:
   - `GET /api/items` → 200, JSON array; `POST /api/items` with JSON body → 201 and echoes parsed body; `PUT`, `DELETE` reach their routes.
   - `/api` and `/api/` both hit the `GET /` endpoint (F14).
   - `/apix/foo`, `/`, `/other` → handler returns `NULL` (fall-through), and `req$PATH_INFO` is untouched afterwards.
   - `/api/nope` → 404 JSON from plumber; `POST /api/items-only-get` → 405 (F14).
   - Endpoint that `stop()`s → 500 JSON from plumber, not HTML.
   - Mount-level failure (simulate with `pr` whose `call` throws) → 500 JSON via our `tryCatch` (F6).
   - Prefix validation: `"api"`, `"/api/"`, `"/"`, `"/session"` are rejected with clear errors at construction.
   - Async: endpoint returns `promises::promise_resolve(list(a=1))`; handler returns a promise; after `promises::then` the value is an `httpResponse` with status 200 (drive with `later::run_now()`).
5. `test-mount.R`, **integration** (live server via `start_app()`): same verbs through real httpuv; binary body (raw PNG bytes) round-trips byte-exact via a `serializer_octet` endpoint; a `future_promise` endpoint returns while a concurrent `/` request completes first (issue the slow request from a separate `callr` process; a shared curl pool serialises them, see DECISIONS.md step 2); page route `/` still served by Shiny; `/www`-style static file still served.

**Implement:**

6. `R/json.R`: `spigot_json()`.
7. `R/rook.R`: `rook_to_httpResponse()`, `json_error()`.
8. `R/api.R`: `spigot_api(file = NULL, envir)` → `plumber::pr(file, envir = envir)` with `pr$setSerializer()` set to a serializer that calls `spigot_json()` itself (one config, one place). A `Plumber` object is returned unchanged (F17).
9. `R/mount.R`: `spigot_mount_handler(pr, prefix, fallback, guard = NULL)` returning `function(req)`. Logic in order: prefix match → `on.exit` restore of `SCRIPT_NAME`/`PATH_INFO` → optional `guard(req)` (M2) → `tryCatch(pr$call(req))` → `promises::hybrid_chain` style: if promise, `then(rook_to_httpResponse)`; else convert directly. `mount_app(app, handler)` asserts `inherits(app, "shiny.appobj")` and `is.function(app$httpHandler)` then replaces the field (F1). This is the only function that knows the appobj shape.
10. `R/app.R` skeleton: `spigot_app(pages = NULL, server = NULL, api, prefix = "/api", ...)` that for now takes `ui` (M5 replaces this) and returns the mounted `shiny.appobj`.

**Exit:** unit + integration tests green; `R CMD check` has no errors; `spikes/` deleted.

### M2: Session binding and request guards

**Tests first** (`test-session.R`):

1. Unit, registry: `fake_session(token)` is a list/R6 with `token`, `userData`, `sendCustomMessage` (records calls), `onSessionEnded(cb)` (stores cb and exposes `end()` to fire it). Assert: `register_session(s)` then `lookup_session(token)` is `s`; after `s$end()` lookup is `NULL`; registering twice is idempotent; tokens are not case-folded.
2. Unit, server wrapper: `wrap_server(user_server)` returns a function with the same formals (`input, output, session`), calls `register_session` first, then the user server; a user server with only `(input, output)` is also accepted (Shiny permits it).
3. Unit, guard via `fake_req()` + mount handler with `guard = session_guard(require_session = TRUE)`:
   - valid header, registered token → endpoint sees `spigot_session(req)` identical to the fake session.
   - header missing → 401 JSON `{"error":"session required"}`; unknown token → 401; token of an ended session → 401; non-hex token (`"../x"`) → 401 without touching the registry.
   - `require_session = FALSE`: missing header → endpoint runs, `spigot_session(req)` is `NULL`; present and valid → bound.
   - `Origin: http://evil.test` with `Host: 127.0.0.1:1234` → 403; matching origin → passes; `Origin` absent but `Referer` cross-host → 403; both absent → passes.
   - Guard rejections short-circuit: the plumber router is never called (spy with a `pr` stub counting calls).
4. Integration: `start_app()` an app whose server records `session$token` to a temp file; from R, POST to `/api/whoami` with that token → 200; with a random token → 401. Oversize body: app started with `max_request_size = 1024`; a 2 KB POST → 413 and the response body is Shiny's plain-text message (F5), so document that this status is not JSON.
5. e2e (chromote, `skip_if_no_chrome()`): tab loads page; `fetch("api/whoami", {headers: {"X-Spigot-Session": Shiny.shinyapp.config.sessionId}})` → 200 with the same token echoed. Closing the tab, then replaying the token from R → 401 within 1 s (registry cleanup on `onSessionEnded`).

**Implement:**

6. `R/session.R`: `.registry <- new.env(parent = emptyenv())`; `register_session()`, `lookup_session()`, `spigot_session(req)` (reads `req$spigot_session`, errors if `req` is not a Rook env), `wrap_server()`.
7. `R/mount.R`: `session_guard(require_session)` + `origin_guard()`; they return `NULL` to continue or an `httpResponse` to short-circuit. Header name constant `SPIGOT_HEADER <- "HTTP_X_SPIGOT_SESSION"`.
8. `R/app.R`: `spigot_app()` wires `wrap_server()`, both guards, and `onStart` that sets `options(shiny.maxRequestSize = max_request_size)` (restore the previous value in `onStop`).

**Exit:** all of the above green; vignette note drafted on why 413 is plain text.

### M3: JS client

**Tests first** (`test-client.R`, all e2e under `skip_if_no_chrome()`; the app fixture serves `spigot_dependency()` plus endpoints `GET /echo-query`, `POST /echo-json`, `GET /fail?status=`, `GET /slow?ms=`):

1. `await spigot.ready` resolves and `spigot.sessionId === Shiny.shinyapp.config.sessionId`. Calling `spigot.get` *before* ready queues until ready (no thrown error).
2. `spigot.get("echo-query", {a: 1, b: "x y", c: [1,2]})` → server saw `a=1&b=x%20y&c=1&c=2`; arrays repeat the key; `null`/`undefined` values omitted.
3. `spigot.post("echo-json", {k: [1]})` → request `Content-Type: application/json`, response parsed object equals input.
4. Non-2xx → rejection is `instanceof SpigotError` with `status`, `message` (from JSON `error` field when present, else statusText) and `body` (parsed JSON or text).
5. `spigot.get("slow", {ms: 3000}, {timeout: 500})` → rejects with `SpigotError` where `status === 0` and `message` mentions timeout; the server request is aborted (`AbortController`).
6. Relative URLs: the test page is served at `/sub/app/` behind a tiny httpuv reverse proxy started in the test (strip `/sub/app`, forward to the Shiny port). `spigot.get("echo-query")` must hit `/sub/app/api/echo-query`. Also verify `spigot.get("/echo-query")` (leading slash) is normalised, not treated as absolute.
7. Header names: `X-Spigot-Session` is sent on every request; a custom `headers` option merges without overriding it.
8. `spigot_dependency()` unit test (no browser): returns an `html_dependency` named `spigot` whose script file exists under `system.file("js", package = "spigot")`.

**Implement:**

9. `inst/js/spigot.js` as a plain ES5-compatible IIFE that assigns `window.spigot` (decision on ES module in §7 Q4; IIFE first because it works with zero build). Contents: `ready` promise resolved on `shiny:sessioninitialized` (`$(document).on("shiny:sessioninitialized", …)`; `config.sessionId` is **not** set yet at `shiny:connected`, see DECISIONS.md step 3), resolving immediately if `Shiny.shinyapp.config.sessionId` is already set when the script runs; `base` computed as `document.baseURI` directory + prefix (prefix injected by `spigot_dependency()` via a `<script>` data attribute or `window.__spigot = {prefix}`); `request(method, path, {query, body, headers, timeout})`; `get`, `post`, `put`, `del`; `SpigotError` class; `on(event, fn)` / `off` registry (used in M4); `Shiny.addCustomMessageHandler("spigot:event", …)` and `"spigot:set-input"` (used in M6).
10. `R/deps.R`: `spigot_dependency(prefix)` → `htmlDependency("spigot", version, src = c(file = "js"), package = "spigot", script = "spigot.js", head = sprintf('<script>window.__spigot={prefix:"%s"}</script>', prefix))`. `spigot_app()` attaches it to every page.

**Exit:** e2e green locally with Chrome; the proxy-prefix test passes.

### M4: Push

**Tests first** (`test-push.R`):

1. Unit: `spigot_emit(fake_session, "cart:changed", list(n = 1))` calls `sendCustomMessage("spigot:event", list(event = "cart:changed", json = "<string>"))` exactly once, and the `json` string parses back to `{"n":1}`. `spigot_emit(NULL, …)` is a no-op with a warning (endpoint called without session).
2. Unit: `spigot_broadcast()` with three registered fake sessions sends to all three; after one `end()`s, only two receive; a session whose `sendCustomMessage` throws (closed socket race) is pruned and does not stop the others.
3. Unit: payload shapes via `spigot_json()`: nested list, `I(1)` → `[1]`, `NA` → `null`, `character(0)` → `[]`, data frame → row objects, named list → object.
4. e2e: two chromote tabs on the same app. Endpoint `POST /ping-me` emits to `spigot_session(req)` only; the calling tab's `spigot.on("ping", …)` fires once, the other tab's never (wait 500 ms). `POST /ping-all` → both fire. Listener registered with `spigot.on` can be removed with `spigot.off`; a second listener for the same event also fires. Payload with `I(1)` arrives as a JS array of length 1.

**Implement:**

5. `R/session.R`: `spigot_emit()`, `spigot_broadcast()`, `prune_session()`.
6. `inst/js/spigot.js`: `spigot:event` handler → `JSON.parse(msg.json)` → listeners by event name, each in `try/catch` so one bad listener does not block the rest.

**Exit:** green; add a "live" section to the reactivity vignette draft.

### M5: Pages

**Tests first** (`test-page.R`):

1. Unit: `spigot_page(template = "<html><head><title>{{title}}</title></head><body>{{#items}}<li>{{.}}</li>{{/items}}{{> foot}}</body></html>", data = list(title = "T", items = 1:2), partials = list(foot = "<p>f</p>"))` → calling the page's render function returns an `html_document`; `as.character()` of it contains `<title>T</title>`, two `<li>`, `<p>f</p>`.
2. Unit: `template` may be a file path (read with `readLines(encoding = "UTF-8")`) or a string; non-ASCII round-trips.
3. Unit: `data = list(title = "{{ Sys.getenv('HOME') }}")` renders the braces literally (whisker escapes HTML; `{{{ }}}` for raw) and never evaluates R (the injection test from M0 step 4).
4. Unit: template without `</head>` → error naming the template. Template with uppercase `</HEAD>` is accepted (case-insensitive split).
5. Unit: `data` may be a function `function(req)` evaluated per request (`req$QUERY_STRING` visible to the template). With `cache = TRUE` and a function `data`, construction errors ("cache requires static data").
6. Integration (`start_app()` with `pages = list("/" = p1, "/about" = p2)`): `GET /` → p1 HTML with `shiny.min.js`, `jquery`, and `spigot.js` each present **exactly once** in `<head>`; `GET /about` and `/about/` → p2; `GET /missing` → 404 with `text/html` and the spigot 404 body; `GET /api/...` still works (mount precedes pages); `POST /about` → 404/405 not a page.
7. Integration: a page with `cache = TRUE` and `data = list(t = Sys.time())`-style value: two requests return identical bodies; with `cache = FALSE` and `data = function(req) list(t = format(Sys.time(), "%OS6"))` two requests differ.
8. Integration: `pages = p1` (single page, not a list) serves it at `/`.

**Implement:**

9. `R/page.R`: `spigot_page()` returns an object of class `spigot_page` holding template text, `data`, `partials`, `cache`, and a `render(req)` closure implementing the §4.3 split + `htmlTemplate(document_ = TRUE)` + `attachDependencies(spigot_dependency())`.
10. `R/app.R`: `page_router(pages)` → `ui <- function(req)` that normalises `PATH_INFO`, picks the page, calls `render(req)`, or returns `httpResponse(404, …)`. `shinyApp(ui, server, uiPattern = ".*")`. Path keys are validated (`^/` and no trailing slash except `/`).

**Exit:** green; `getting-started.Rmd` can be written against the real API.

### M6: Reactive bridge

**Tests first** (`test-trigger.R`):

1. Unit: `spigot_trigger(fake_session, "cart", list(n = 2))` sends `sendCustomMessage("spigot:set-input", list(name = "cart", json = "<string>"))`. Name validation: must match `^[A-Za-z][A-Za-z0-9_.-]*$`, else error. `NULL` session → error (a trigger without a session is meaningless, unlike emit).
2. e2e: app server has `observeEvent(input$cart, spigot_emit(session, "cart:observed", input$cart))`. From the tab: `await spigot.post("cart/add")` (endpoint calls `spigot_trigger(s, "cart", x)`) → `spigot.on("cart:observed")` fires exactly once with payload `x`.
3. e2e: five rapid POSTs with the **same** value → observer fires five times (`priority: "event"`), measured by a counter in the tab.
4. e2e: trigger latency median < the bound recorded in `DECISIONS.md` step 5 (regression guard, generous: 5× the spike's p95).
5. e2e: the value shape passes through `spigot_json()` → `JSON.parse` → `setInputValue` so `I(1)` arrives in R as a length-1 list, and `NA` as `NULL`. Document this in the vignette.

**Implement:**

6. `R/session.R`: `spigot_trigger()`.
7. `inst/js/spigot.js`: `spigot:set-input` handler → `Shiny.setInputValue(msg.name, JSON.parse(msg.json), {priority: "event"})`.

**Exit:** green; reactivity vignette complete.

### M7: Examples, docs, release prep

1. `inst/examples/minimal`: one page, `GET /api/hello`. `inst/examples/live`: counter with `spigot_emit` + `spigot_trigger`. `inst/examples/site`: three pages, partials, one `future_promise` endpoint. Each has an `app.R` that calls `spigot_app()`.
2. Smoke test `test-examples.R`: for each example, `start_app()` it, `GET /` is 200 and contains `spigot.js`, one API call returns 200. Runs under `skip_on_cran()`.
3. Vignettes: `getting-started.Rmd` (walks `minimal` then `site`), `reactivity.Rmd` (§2 expanded, with the three channels and when to use each, plus the concurrency warning from §4.6).
4. `devtools::document()`; every exported function has `@param`, `@return`, `@examples` (wrapped in `\dontrun{}` where a server is needed).
5. `devtools::check()` clean: 0 errors, 0 warnings, 0 notes other than the usual "new submission".
6. CI (`.github/workflows/R-CMD-check.yaml`): matrix of R release / oldrel × shiny CRAN / shiny GitHub `main`, plumber CRAN. Chrome via `browser-actions/setup-chrome` or `chromote::local_chrome_version()` in a setup step. e2e tests `skip_if_no_chrome()` so a matrix cell without Chrome still runs unit + integration.
7. Lower the `shiny` version pin: add a matrix cell with the oldest shiny that passes (try 1.8.0; F1/F4/F9 have been stable since well before that). Pin to the oldest green version.
8. Tag `v0.1.0`.

## 7. Open questions

1. Expose plumber filters (auth/logging) per app, or wrap them in `spigot_*` helpers?
2. File uploads: route through plumber multipart, or keep Shiny's `fileInput` channel? (Note F5: either way the limit is `shiny.maxRequestSize`.)
3. Should `spigot_session()` also expose `session$userData` helpers for typed per-tab state?
4. Should `spigot.js` ship as plain IIFE only (M3 default), or also an ES module generated from the same source?
5. Docs page: serve `openapi.json` at `{prefix}/openapi.json` for dev only (`options(spigot.dev = TRUE)`)? plumber's `pr$getApiSpec()` makes this cheap.
6. Should the origin guard be configurable (`allow_origins =`) for apps embedded in iframes on another host?

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Shiny changes `shiny.appobj` fields or `hybrid_chain` handling (F1, F4) | Mount breaks | Isolate in `mount.R`; assert structure at startup and fail loudly; CI against shiny `main` |
| Sync endpoint blocks all sessions | Perceived hangs | Docs; optional dev-mode warning when a handler exceeds N ms |
| Session token exposure | Another user replays the token | Token is per-tab and already sent over the same websocket; HTTPS assumed; tokens die with the session; origin guard |
| Template injection through `htmlTemplate` | Remote code execution | Never pass whisker output through `htmlTemplate` text; only through `HTML()` values (§4.3, M5 test 3) |
| `auto_unbox` / JSON shape drift | Frontend bugs | Single serializer `spigot_json()`; tests on shape edge cases in M1, M4, M6 |
| 413 responses are plain text from Shiny, not JSON (F5) | Client parsing surprise | `SpigotError.body` falls back to text; documented |
| plumber 1.x enters maintenance-only status | Long-term | Keep plumber usage behind `api.R`, `rook.R`, and `mount.R`. A plumber2 backend would be the sidecar design, a separate decision |
| No Chrome on a CI runner or dev box | e2e silently skipped | `skip_if_no_chrome()` prints a visible skip; CI has at least one cell with Chrome and treats skips there as failures (`testthat::set_max_fails`/custom reporter) |
