# DECISIONS

One dated entry per decision. M0 evidence came from `spikes/`, deleted in M1
(recover it from the `first commit` in git history); M1+ evidence lives in
`tests/testthat/`. Re-run the relevant spike or test when bumping shiny or plumber.

Environment for all M0 entries: R 4.5.2, Ubuntu 26.04.1, shiny 1.14.0,
plumber 1.3.3 (CRAN), httpuv 1.6.17, whisker 0.4.1, htmltools 0.5.9,
promises 1.5.0, future 1.70.0, chromote 0.5.1, Chrome for Testing
(chrome-headless-shell) 155.0.8059.79.

## 2026-10-15 — M0 step 0: environment and browser for e2e tests

- plumber 1.3.3 was already installed (PLAN §4.0 said it was not). chromote 0.5.1 was installed from CRAN.
- **Browser:** `chromote::local_chrome_version("latest-stable", binary = "chrome-headless-shell")`
  downloads Chrome for Testing into `~/.cache/R/chromote/chrome/`. No system Chrome is used.
  CI uses the same call in a setup step, so local runs and CI run the same binary.
- **Sandbox:** Ubuntu 23.10+ sets `kernel.apparmor_restrict_unprivileged_userns = 1`, so
  Chrome aborts with `FATAL ... No usable sandbox!`. The fix is
  `chromote::set_chrome_args(c(chromote::default_chrome_args(), "--no-sandbox"))`.
  This is acceptable because the browser only loads our own localhost test app.
  `helper-chrome.R` applies it on Linux. The alternative needs root: an AppArmor
  profile for the downloaded binary.
- Name check: `spigot` is not on CRAN or in the CRAN archive, and no R repo of that name
  turned up on GitHub. (Spigot is also a well-known Minecraft server project, so web
  searches are noisy, but there is no R-package conflict.)

## 2026-10-15 — M0 step 1: mount via `app$httpHandler` (`spikes/01-mount.R`)

- GET, POST (JSON echo), PUT and DELETE all reach plumber through the wrapped
  `httpHandler` over real httpuv. Shiny still serves `/`. **F1, F3 confirmed.**
- A wrong verb on an existing path gives **405**. **F14 confirmed.**
- After stripping `/api` from `PATH_INFO = "/api"`, the result is **`""`**. Mapping `""` to `"/"`
  makes `/api` and `/api/` both hit `GET /`. plumber sees `PATH_INFO = "/pathinfo"` (prefix
  gone), with the prefix moved to `SCRIPT_NAME`.
- Calling `rook.input$read()` before `pr$call()` without a rewind makes plumber see an empty body
  (`[]`). After `rewind()` it recovers (`{"a":[1]}`). **Rule: never pre-read; if you must,
  rewind.** **F13 confirmed.**
- plumber's default serializer boxes scalars (`{"root":[true]}`). This confirms that
  `spigot_api()` must install a `spigot_json()`-compatible serializer (M1 step 8).

## 2026-10-15 — M0 step 2: promise returned from `httpHandler` (`spikes/02-promise.R`)

- `GET /slow` returns `promises::future_promise({Sys.sleep(2); ...})` under `multisession`.
  The wrapper returns `then(pr$call(req), rook_to_httpResponse)`. Result: 200 `{"ok":[true]}`
  after 2.16 s, and a concurrent `GET /api/` completed in **8 ms** while `/slow` was pending.
  **F4 confirmed; the process is not blocked.**
- **Test-harness gotcha:** the first attempt used `curl::curl_fetch_multi` on one pool. Both
  requests finished at ~2.4 s because the client serialised them. Concurrency tests must issue
  the slow request from a separate process (`callr::r_bg`), or use separate connections.
  M1 integration test 5 must follow this.

## 2026-10-15 — M0 step 3: session token on the JS side (`spikes/03-token.R`)

- `Shiny.shinyapp.config.sessionId === session$token` in 5/5 tabs. The token is 32 lowercase hex
  chars. **F7 confirmed.**
- **Correction to PLAN (§3, M3 step 1/9):** `config.sessionId` is **not** set at `shiny:connected`.
  It arrives in the server's `config` message, about 2–6 ms later. shiny.js sets
  `this.config` and then triggers `shiny:sessioninitialized` in the same handler
  (shiny.js 1.14.0 l. 6955–6963). In all 5 runs: undefined at `shiny:connected`, defined at
  `shiny:sessioninitialized`.
- **Decision:** `spigot.ready` resolves on `shiny:sessioninitialized`. If the script runs after
  that event has fired, it resolves immediately when `Shiny.shinyapp.config.sessionId` is
  already set. (`Shiny.initializedPromise` also exists in 1.14.0, but it is not documented
  public API, so we do not depend on it.)
- Timing: the token is available about **9–15 ms after DOMContentLoaded** on localhost.

## 2026-10-15 — M0 step 4: whisker page + Shiny deps (`spikes/04-page.R`)

- Approach adopted as specified in PLAN §4.3:
  1. Render the full template with whisker (partials included).
  2. Split the **rendered output** once at the first `</head>`, matched case-insensitively.
  3. Pass the two halves as `HTML()` into the fixed template
     `"{{ head }}{{ headContent() }}</head>{{ rest }}"` with `document_ = TRUE`.
- Results in Chrome: exactly 1 shiny script and 1 jQuery, both inside `<head>`. One `<head>` and
  one `<body>`. Shiny connects. `<HEAD>` in uppercase works. `lang` is kept. Non-ASCII
  (`Größe – ✓`) round-trips. Items and partials render.
- **Injection test:** `data = list(title = "{{ Sys.getenv('HOME') }}")` renders literally, via both
  `{{ }}` and `{{{ }}}`. `$HOME` appears nowhere in the response. Negative control: option B
  (`htmlTemplate(text_ = whisker_output)`) **does** evaluate it, so option B stays rejected.
- **Split rule:** split the rendered output, not the template. That way a `</head>` inside a
  partial (e.g. `{{> head}}`) works. A triple-stache value containing `</head>` could move the
  split. That is not an escalation: `{{{ }}}` already means "raw HTML", and both halves are
  `HTML()`, so nothing gets re-templated. At render time, no `</head>` → error. At construction
  time, `spigot_page()` errors if neither the template nor any partial contains `</head>`.
- Shiny adds its own `<meta http-equiv="Content-Type" ...>` after the user's head content. A
  duplicate charset meta is harmless.

## 2026-10-15 — M0 step 5: reactive bridge latency (`spikes/05-trigger.R`)

50 sequential iterations in headless Chrome against localhost, after 5 warm-up iterations:

| Leg | median | p95 | max |
|---|---|---|---|
| HTTP round-trip (`fetch` POST /api/tick) | 3.1 ms | 3.4 ms | 5.5 ms |
| fetch start → `spigot:set-input` received | 2.6 ms | 3.7 ms | 33.0 ms |
| set-input → pong (`setInputValue` → observer → message) | 41.8 ms | 43.1 ms | 44.7 ms |
| **fetch resolve → pong (decision metric)** | **41.3 ms** | **42.7 ms** | 74.1 ms |
| Baseline: plain `Shiny.setInputValue` → observer → pong, no HTTP | 42.2 ms | 43.1 ms | 44.6 ms |

- **Decision: option 1 (round-trip via `spigot:set-input`) adopted; option 2 closed.** p95 of 42.7 ms
  is under 50 ms.
- The ~40 ms floor is Shiny's own input → observer → output path: the plain-Shiny baseline is the
  same. The bridge adds only the push leg (~3 ms), so option 2 would not have removed the floor.
- The push message arrived *before* `fetch` resolved in 5/50 cases. Server pushes go out during
  the handler, before the HTTP response. Client code must not assume HTTP-response-then-push
  ordering. This goes in the reactivity vignette.
- **M6 regression bound** (5 × spike p95): trigger latency median **< 215 ms**.

## 2026-10-15 — M1: httpuv static paths answer API POSTs with 400 (F16)

- **Found by** the M1 integration fixture, which is an app *directory* with `www/`. Every API
  `POST` returned plain-text `400 Bad Request`, while `GET` worked. The M0 spikes missed this
  because they ran `shinyApp()` objects, which have no static path at `/`.
- **Cause:** `shinyAppDir()` registers `www/` as an httpuv static path at `/` (fallthrough).
  httpuv answers non-GET requests under a static path itself, on its I/O thread, before R sees
  them. Shiny excludes its own `/session` with `excludeStaticPath()` for the same reason.
  `startHttpuvApp()` builds the static paths from the **outer** appobj, so the inner appobj
  returned by `app.R` cannot add an exclusion. This affects every deployed app dir with `www/`
  (Shiny Server, Connect).
- **Decision:** `mount_app()` wraps `onStart`. It calls `later::later()` to run
  `getShinyOption("server")$setStaticPath(<prefix> = excludeStaticPath())` on the first
  event-loop tick. `onStart` runs before the httpuv server exists; `shinyOptions(server =)` is
  set right after it. Shiny's exported `addResourcePath()` uses the same server handle, and
  `WebServer$setStaticPath()` is public httpuv API. Scratch check: without the fix POST → 400;
  with it POST/GET → 200 and `www/` files are still served. This also keeps a `www/api/` folder
  from shadowing API GETs.
- **Residual window:** a non-GET API request that arrives between `listen()` and the first loop
  tick still gets 400. Page loads go through the same later queue, behind the exclusion, so a
  browser cannot hit this window. With M2's `require_session = TRUE` an API call needs a loaded
  page, so the window is closed in practice.
- Regression guard: `test-mount.R` integration tests (fixture `apps/mount/` has `www/`).

## 2026-10-15 — M1: plumber binds the default serializer at endpoint creation (F17)

- `pr$handle()` (and so `pr_get()` etc.) copies `private$default_serializer` into the endpoint
  **when the endpoint is created**. Endpoints parsed from a file without `@serializer` store
  `NULL` and use the router default at request time.
- So `pr$setSerializer()` after `pr() |> pr_get(...)` has no effect on those endpoints. The
  M1 step 8 plan (set the serializer on a router passed in) could not work.
- **Decision:** `spigot_api(file = NULL)`. `NULL` returns an empty router that already has the
  `spigot_json()` serializer, so routers built in code start from it:
  `spigot_api() |> pr_get(...)`. A file path → `pr(file)` + serializer (works, see above). A
  `Plumber` object is returned **unchanged and not mutated**: its endpoints keep their
  serializers. `spigot_app(api = <Plumber>)` uses it as given.

## 2026-10-15 — M1: request env fidelity and mount details

- httpuv sets **both** `CONTENT_TYPE` and `HTTP_CONTENT_TYPE` (and both `CONTENT_LENGTH`
  forms), plus `HEADERS` (named, lowercase) and `REMOTE_PORT`. plumber reads
  `HTTP_CONTENT_TYPE`. `fake_req()` mirrors this (checked against a live httpuv request).
- Binary request bodies need `parsers = "octet"` on the endpoint. plumber's default parser set
  falls back to text, and `rawToChar()` fails on NUL bytes (500). This is ordinary plumber
  usage; the getting-started vignette should mention it.
- `spigot_mount_handler()` forces `fallback`. Otherwise `mount_app()`'s
  `fallback = app$httpHandler` is a lazy promise, first evaluated after the field is replaced,
  so the handler calls itself (`node stack overflow`, seen as Shiny's HTML 500 on `GET /`).
- The rewritten `PATH_INFO`/`SCRIPT_NAME` are restored when the request finishes. For async
  results that is in `promises::finally()`, not `on.exit()`, because plumber routes after async
  filters resolve. Test: "the prefix stays stripped until an async filter has finished routing".
- Mount-level failures (sync or async) → `{"error":"internal server error"}` 500. The condition
  message goes to stderr via `message()` and never to the client.
- Prefix rule: `^(/[A-Za-z0-9._~-]+)+$`. The first segment must not be `session` or `shared`
  (Shiny serves both itself).

## 2026-10-15 — M2: integration tests open Shiny sessions without a browser

- `open_session(url)` (`helper-server.R`) connects a `websocket::WebSocket` to
  `/websocket/` and sends `{"method":"init","data":{}}`. Shiny answers
  `{"config":{"workerId":"","sessionId":"<token>","user":null}}` on connect, runs the
  server function after `init`, and then flushes `{"errors":{},"values":{},...}`. The helper waits for
  that flush, so the session is registered before the first API call. Closing the
  socket fires `onSessionEnded` (scratch check: START/END both logged).
- So session integration tests (401/200, token dies with the session, 413) need no Chrome.
  Chrome is only used for what needs a real browser: the `Origin` header a browser POST
  sends, and closing a tab. `websocket` (already a chromote dependency) and `chromote` are
  in Suggests.
- `helper-chrome.R` does not download. It uses a browser on the PATH, else the cached
  Chrome for Testing headless shell (`chromote::chrome_versions_list("installed")`). It
  skips with the install command when neither exists.

## 2026-10-15 — M2: session registry and server wrapper

- One process-global registry (`.registry`, token → session). A token from another spigot
  app **in the same R process** would be accepted by this app's API. Deployed apps run one
  app per process (Shiny Server, Connect, `runApp`), so this is accepted for now. Revisit
  if `spigot_broadcast()` (M4) needs per-app scope.
- `register_session()` is idempotent: a second call for the same session adds no second
  `onSessionEnded` callback. Removal only deletes the entry if it is still that session.
- `lookup_session()` also treats `session$isClosed()` as gone. This covers any gap between the
  socket closing and `onSessionEnded` running.
- `wrap_server()` always has formals `(input, output, session)` and calls the user's function
  with the arguments Shiny would give it. It mirrors `shiny:::argsForServerFunc()`: `session` and
  `clientData` only when named in its formals; `...` does not receive them. **F20.**

## 2026-10-15 — M2: origin guard rules

- `Origin` is used when present, else `Referer`. With neither, the request passes (same-origin GET).
- The source's `scheme://authority` is compared, case-insensitively, with `Host` and with
  every entry of `X-Forwarded-Host` (comma-separated). `:80` is dropped for http and `:443`
  for https on both sides. `Origin: null`, userinfo (`user@host`), non-URLs, and a source with
  no `Host` to compare against → 403.
- Accepting `X-Forwarded-Host` does not weaken the guard. A cross-site page cannot set that
  header without a CORS preflight, and the API never answers a preflight with CORS headers.
  Likewise, a cross-site `fetch` cannot send `X-Spigot-Session` without a preflight. So with
  `require_session = TRUE` the session check alone already blocks CSRF, and the origin guard
  is defence in depth. With `require_session = FALSE` it is the only CSRF guard.
- **Not verified here (no deployment on this machine):** whether Shiny Server and Posit Connect
  keep `Host` or set `X-Forwarded-Host`. If a proxy rewrites `Host` and sets neither, every browser
  POST gets 403. Check this on a real deployment before M7. PLAN §7 Q6 (`allow_origins`) is the escape hatch.
- The origin check runs before the session check: a cross-origin request gets 403 even with a valid token.

## 2026-10-15 — M2: `max_request_size` defaults to `NULL` (changes PLAN §3)

- PLAN §3 had `max_request_size = 5 * 1024^2`. That would silently override an
  `options(shiny.maxRequestSize = ...)` the user set themselves. **Decision:** default `NULL`
  leaves the option alone (Shiny's own default is 5 MB). A number sets it in `onStart`.
  `shiny::onStop()` (registered inside `onStart`, so it is app-level) restores the old value.
  `Inf` means no limit. Values `<= 0` are rejected, though Shiny would read them as unlimited.
- Shiny's httpuv `onHeaders` reads the option **per request**, so setting it in `onStart`
  works. A body with `Transfer-Encoding` and no `Content-Length` counts as size `Inf`, so it
  **always** gets 413 while any finite limit is set. **F19.**
- The 413 body is Shiny's plain text (`Maximum upload size exceeded`). This is documented in the
  `spigot_app()` "Request size" section, which is the draft for the vignette note.

## 2026-10-15 — M2: the minimal example sends the token itself until M3

- `require_session = TRUE` is the default, so `inst/examples/minimal/www/app.js` now waits for
  `shiny:sessioninitialized` and sends `X-Spigot-Session`. `spigot.js` (M3) will replace this.
- Gotcha caught by the e2e test: the script's own `const $ = (id) => ...` shadows jQuery's `$`
  across the whole script (temporal dead zone). Use `jQuery(document)` explicitly.

## 2026-10-15 — M3: how spigot.js learns the prefix (changes PLAN M3 step 10)

- PLAN had `spigot_dependency()` set `window.__spigot = {prefix}` with the dependency's `head`
  field. htmltools' `renderDependencies()` writes `head` **after** the dependency's `<script>`,
  so the global would not exist yet when `spigot.js` runs.
- **Decision:** the script tag carries it, `<script src=".../spigot.js" data-prefix="/api">`
  (`script = list(src, data-prefix)`; htmltools ≥ 0.5 renders attribute lists). `spigot.js` reads
  `document.currentScript`. No inline script, so it also works under a CSP without
  `unsafe-inline`. The prefix goes through `check_prefix()`, which only admits
  `[A-Za-z0-9._~-]` segments, so it cannot break out of the attribute.
- `spigot_app()` wraps `ui` in `attach_spigot()`, a `function(req)` that calls the user's ui the
  way Shiny does (`ui(req)` if it has formals, else `ui()`), passes an `httpResponse` through,
  and `attachDependencies(append = TRUE)`s the rest. Shiny puts jQuery and shiny.js first, so
  `spigot.js` always loads after them (asserted in `test-client.R`).
- Gotcha caught by the integration test: `attach_spigot()` must `force(ui)`. `spigot_app()` does
  `ui <- attach_spigot(ui, ...)`, so an unforced promise evaluates to the wrapper itself and
  the page fails with "infinite recursion". A unit test now reproduces the reassignment.

## 2026-10-15 — M3: spigot.js behaviour

- `spigot.base` = `prefix` (leading slash dropped) + `/`, resolved against `document.baseURI`, so
  it is the API **next to the page**. Writable. Paths have leading slashes stripped. A request's
  URL is fixed when the call is made, even if it then waits for `ready`.
- **For M5:** a page at a nested path (`/docs/intro`) would resolve `api/` to `/docs/api/`. Shiny's
  own relative dependency URLs (`shared/shiny.min.js`) break the same way there, so nested
  pages need a `<base href>` to the app root anyway; `spigot.base` follows it with no change.
- `spigot.ready` resolves on `shiny:sessioninitialized` (M0 step 3), or immediately if the
  token is already set. The header value is read from `Shiny.shinyapp.config.sessionId` at
  send time, so after a Shiny reconnect requests use the new token. The header is set last:
  `options.headers` cannot override it (any case).
- Bodies: `FormData`, `Blob`, `URLSearchParams`, `ArrayBuffer`/views and `ReadableStream` are
  sent unchanged; **everything else, strings included, is JSON** with
  `Content-Type: application/json`. A string sent raw would arrive as `text/plain`, which
  plumber does not parse as JSON; text goes in a `Blob`. `Accept: application/json` by default.
- Replies: empty → `null`; `Content-Type` `*/json` or `*+json` that parses → the value; anything
  else → text. Non-2xx → `SpigotError(status, message, body)`, `message` = the JSON `error`
  field if it is a string, else `statusText`, else `HTTP <status>`. No reply → `status` 0:
  `"... timed out after <n> ms"` or `"... failed: network error (...)"`.
- `timeout` counts from the call (including any wait for `ready`), then aborts the fetch via
  `AbortController`. The e2e test checks the fetch's `signal.aborted`. No default timeout yet;
  PLAN §4.6 `spigot_options(timeout =)` will supply one.
- `SpigotError` is ES5-style (`Object.create(Error.prototype)`), so `instanceof Error` holds.
  It lives at `spigot.SpigotError`, not on `window`.
- `spigot.on/off` and the `spigot:event` / `spigot:set-input` handlers (PLAN M3 step 9) are not
  in M3. They are written in M4 and M6 with the tests that cover them.

## 2026-10-15 — M3: subpath test proxy

- `helper-proxy.R` `start_proxy()` runs a reverse proxy in a `callr` process: httpuv
  `runServer()` for HTTP (forwarded with a synchronous `curl` call) and websockets (bridged to a
  `websocket::WebSocket` client, messages buffered until the upstream opens). It strips
  `/sub/app`, and like nginx defaults it **rewrites `Host`** to the upstream and sets
  `X-Forwarded-Host`.
- So the e2e test also proves, with a real browser POST, that the origin guard accepts
  `X-Forwarded-Host` behind a proxy that rewrites `Host`. Whether Shiny Server and Posit Connect
  behave like this proxy is still unverified (M2 entry).
- Gotcha: `callr` `read_all_output_lines()` blocks until the process exits; use
  `read_output_lines()` to peek at a live proxy.

## 2026-10-15 — 401 responses carry a `hint`

- Calling the API by hand (curl, Postman) against an app with `require_session = TRUE` gave a bare
  `{"error":"session required"}`. The 401 body is now
  `{"error": "session required", "hint": "You may be interested in spigot_app(..., require_session = FALSE)."}`.
  `error` is unchanged, so `SpigotError.message` in spigot.js is the same.
- The hint is deliberately terse and the same for every 401: it points a developer at the setting
  so they can troubleshoot from the docs, and says nothing about tokens, the header, or how to
  borrow a live tab's session. A first draft that explained all of that was rejected as too
  strong a pointer for a caller who should not be using the API.
- It still tells any caller that the server is a spigot app. Accepted: nothing secret is revealed.

## 2026-10-15 — M4: push

- `ShinySession$sendCustomMessage()` writes to the websocket immediately (shiny 1.14.0:
  `sendMessage()` → `write()` → `websocket$send()`), not at the next flush, and silently does
  nothing once the session is closed. So an endpoint can emit without a reactive context, and
  an event can reach the page before the endpoint's HTTP reply (as M0 step 5 measured).
- Message: `sendCustomMessage("spigot:event", list(event, json))`, where `json` is a plain
  string from `spigot_json()`, so Shiny's own `toJSON()` (different `dataframe`/`digits`
  settings) never shapes the payload. `spigot.js` `JSON.parse`s it. `spigot_broadcast()`
  serialises once for all sessions.
- `spigot_emit(NULL, ...)` warns and returns `FALSE` (an endpoint run with
  `require_session = FALSE` and no token). A non-session object errors. Event names: any
  non-empty string, in R and JS.
- `spigot_broadcast()` sends to every session in the registry, skipping and pruning any that
  `isClosed()` or whose send throws, silently: a closed-socket race is expected, not an error.
  It returns the number reached. **Scope:** the registry is process-global (M2 entry), so
  broadcast reaches every spigot app's sessions **in this R process**. Kept: deployments run
  one app per process. Revisit with a per-app registry only if that changes.
- JS: `spigot.on(event, fn)` returns an unsubscribe function; adding the same `fn` twice is a
  no-op (as `addEventListener`); `spigot.off(event)` with no `fn` removes all of that event's
  listeners. Listeners run on a copy of the list, so one may `off` itself mid-dispatch.
  A throwing listener does not stop the rest; its error is rethrown in a `setTimeout`, so it
  still reaches the console and `window.onerror`, as a DOM listener's error does. Listeners
  get `(data, event)` with `this === spigot`.
- `spigot_broadcast(except =, filter =)`, added for multi-user pages (one tab's action updates
  the others; chat rooms). `except`: a session or list of sessions, compared by identity after
  `rootScope()`, because a module's `session` is a `session_proxy` that is never `identical()`
  to the registered root (Shiny's real proxy is used in the test). `filter(session)` must return
  `TRUE`/`FALSE`; it runs for every open session **before** any send, so a failing filter sends
  nothing rather than half a broadcast. Rooms are just `filter` over `session$userData`; a
  `spigot_join()`/`room =` API waits for a real need.
- Multi-user reach is one R process. Open-source Shiny Server runs one process per app; Posit
  Connect can start several (max processes / connections per process), and users in different
  processes do not see each other's broadcasts. Cross-process push needs an external relay
  (Redis, Postgres `LISTEN/NOTIFY`) and is out of scope. Document for M7.
- No replay: events that arrive before the page calls `spigot.on()` for them are dropped.
- The "live" vignette draft is the `spigot_emit()` help page (one tab vs all, shapes,
  push-before-reply ordering, emit from the main process not a `future` worker).
- Integration tests read pushes from the websocket without Chrome: `open_session()` now
  returns `custom(type)`.

## 2026-10-16 — M5: `pages` replaces `ui`, and takes Shiny UI too

- `spigot_app(pages, ...)` replaces the temporary `ui` argument (PLAN §3). `pages` is one page,
  served at `/`, or a named list keyed by path. A plain (unclassed) list is a list of pages;
  anything classed (a `spigot_page`, a `tagList`, an `html_document`) or a function is one page.
- A page is a `spigot_page()` **or anything `shinyApp()` takes as `ui`** (`fluidPage()`,
  `htmlTemplate()`, `function(req)`, an `httpResponse`). This keeps Shiny UI available as an
  opt-in, per the §1 non-goals, and let every M1–M4 fixture switch from `ui =` to `pages =`
  with no other change.
- `spigot_page()` attaches no dependency itself. `spigot_app()` attaches `spigot_dependency()`
  to every page in `attach_spigot()`, as in M3, so spigot.js is attached in one place for both
  kinds of page (changes PLAN M5 step 9). `attach_spigot()` now passes `NULL` through.

## 2026-10-16 — M5: page paths are one segment; a trailing slash redirects

> Path rule superseded by "nested pages get a `<base href>`" below; the redirect and routing
> notes still hold.

- Shiny writes its dependency URLs relative (`jquery-3.7.1/jquery.min.js`). A page at
  `/docs/intro`, or at `/about/`, resolves them under `/docs/` or `/about/` and loads no Shiny,
  so no session and no API. The M3 entry suggested a `<base href>`. **Rejected for now:**
  injecting one silently changes the user's own relative links, and turns `href="#section"`
  into a link to the app root.
- **Decision:** a page path is `/` or one segment (`^/[A-Za-z0-9._~-]+$`, not `/session` or
  `/shared`, and not under the API prefix). Nested pages are an error at `spigot_app()` time;
  support them later only if a site needs them (then `<base href>` is the likely answer).
- `/about/` gets `301` with `Location: ../about` plus the query string, instead of serving the
  page there (PLAN §4.3 said "normalised"). The relative `Location` stays correct under a proxy
  subpath: the e2e test opens `/sub/app/about/` through `start_proxy()` and lands on
  `/sub/app/about` with a working session. A trailing slash on an unknown path is a 404.
- Routing is `shinyApp(uiPattern = ".*")` with `page_router()` as the ui function (F10). Unknown
  paths get a fixed HTML 404 that does not echo the path. Under `runApp()`, `shared/`, every
  dependency directory and `www/` are httpuv static paths (`startHttpuvApp()`,
  `addResourcePath()`), so the catch-all shadows only Shiny's R-level handlers after the app's:
  `/reactlog` and `/reactlog/mark`, which `page_router()` returns `NULL` for.
- Only `GET` reaches a page (Shiny's `uiHttpHandler`, F3). A `POST /about` gets Shiny's 404, or
  httpuv's plain-text 400 in an app directory with `www/` (F16).

## 2026-10-16 — M5: templates

- A `template` (or partial) string containing `<`, `{{` or a line break is template text;
  anything else is a file path, read as UTF-8 **when `spigot_page()` runs**, relative to the
  working directory (the app directory under `runApp()`). A missing file is an error naming it.
  Shiny's autoreload re-sources `app.R` when an `.html` file changes, so reading once is fine
  in development.
- whisker sees only `data`: a global or a local variable of the same name renders empty
  (checked, also for `{{HOME}}`). It escapes `&`, `<`, `>`, `"`, **not `'`**; `?spigot_page`
  says to use double-quoted attributes. whisker has no lambdas (a function value renders empty).
- whisker reads `<name>.mustache` from the working directory for a partial it was not given.
  spigot does not want two sources of partials: `spigot_page()` checks every `{{> name}}` tag
  against `partials` at creation, and `render_whisker()` renders from an empty temp directory
  and turns whisker's "No partial" warning into an error (this covers tags after a delimiter
  change, which the creation check cannot see).
- `</head>` must be in the template or a partial at creation (M0 step 4), matched as
  `</head\s*>` in any case; a render whose output has none is an error.
- `data` is a named list, or a function called per request (with `req` if it takes an
  argument, as Shiny calls `ui`). `cache = TRUE` memoises the rendered `html_document` on the
  first request and needs list `data`. Since list data is static, a cached and an uncached page
  render the same HTML; the unit test counts `render_whisker()` calls instead.
- The minimal example now uses `spigot_page("index.html")`; its template lost
  `{{ headContent() }}`.

## 2026-10-16 — M5: nested pages get a `<base href>` (supersedes one-segment paths)

- Nested pages matter for sites (`/docs/intro`), so the one-segment rule went. A path is `/` or
  one or more segments of `[A-Za-z0-9._~-]`, with no `.`/`..` segment, not under `/session`,
  `/shared` or the API prefix.
- What breaks at depth, checked in shiny.js 1.14.0: **only relative asset URLs.** The websocket
  URL is built from `location.pathname` (`createSocket()`: pathname + `/` + `websocket/`), so a
  page at `/about` already connects to `/about/websocket/`, and Shiny's server accepts any ws
  path but `/autoreload/`. Hosts that set `Shiny.createSocket` (Shiny Server's SockJS, Connect)
  replace this; not verified on a real deployment (same caveat as the M2 origin-guard entry).
- **Decision:** a `spigot_page()` served below the top level gets `<base href="../" data-spigot>`
  (one `../` per level, relative so it works under a proxy subpath) right after its `<head>`
  tag, before anything else in the head. Relative URLs then resolve from the app root on every
  page; top-level pages get no base and are unchanged. A template with its own `<base>` keeps
  it. No `<head>` tag at depth → render error (inserting before `<!DOCTYPE>` would break the
  page). The cache holds the HTML before the base, since one page object can be served at
  several depths.
- **Nested pages must be `spigot_page()`s.** For tag-based Shiny UI, `renderPage()` writes
  Shiny's scripts before any `tags$head()` content (checked), so a base added there comes too
  late. Error at `spigot_app()` time.
- **Fragment links:** with a base, `href="#sec"` resolves to the app root (the e2e test saw the
  click land on `/`). `spigot.js` adds one delegated `click` listener: when `base[data-spigot]`
  exists, a plain left click on `<a href="#...">` (no modifier, no other `target`, not already
  `defaultPrevented`) sets `location.hash` instead. Middle-click/new-tab on such a link still
  opens the root, and `href="?tab=2"` still resolves from the root; both documented in
  `?spigot_page`.
- Trailing slash at any depth: `/docs/intro/` → 301 `../intro` (plus query). `//` is a 404.
