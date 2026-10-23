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
  *Superseded in M9: the request is no longer restored.*
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
  (Answered 2026-10-23, below: nginx in front of Shiny Server sets neither.)
- The origin check runs before the session check: a cross-origin request gets 403 even with a valid token.

## 2026-10-23 — origin guard trusts `Sec-Fetch-Site` first

- Seen on a real deployment, nginx in front of Shiny Server open source at a subpath: a page
  `GET` from Firefox, with `Referer: https://<host>/dashboard/app/` and
  `Sec-Fetch-Site: same-origin`, got 403. R saw a rewritten `Host` and no `X-Forwarded-Host`, so
  the `Referer` fallback refused every same-origin request, not only POSTs.
- **Decision:** when `Sec-Fetch-Site` is present it decides: `same-origin` or `none` pass, and
  anything else (`same-site`, `cross-site`, unknown) gets 403. Without it, the Origin/Referer vs
  Host rules above apply unchanged.
- Pages cannot set `Sec-Fetch-*` (forbidden header names), and it needs no `Host`, so it holds
  behind any proxy. Every current browser sends it (Chrome 76, Firefox 90, Safari 16.4). Non-browser
  clients can forge it, but they can forge `Origin` too, and CSRF is a browser problem.
- `same-site` is refused: a sibling subdomain is a different origin, which matches what the Host
  comparison already did.
- `allow_origins` (PLAN §7 Q6) is still not built. It is only needed for browsers without
  `Sec-Fetch-Site` behind such a proxy.

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

## 2026-10-16 — M6: `spigot_trigger()` passes the value by reference (changes PLAN §4.5, M6)

- PLAN M6 sent the value as a `spigot_json()` string for the page to `JSON.parse` and pass to
  `Shiny.setInputValue()`. Checked in shiny 1.14.0 (`shiny:::applyInputHandler()`): an input
  with no `:type` whose value is an unnamed list is `unlist(recursive = TRUE)`ed. So `I(1)`
  arrived as `1`, not a length-1 list (PLAN M6 test 5 was wrong), a data frame as one flat
  named vector, and `NA` as `NULL`, which a default `observeEvent()` (`ignoreNULL = TRUE`)
  ignores. **F21.**
- **Decision (Kent, 2026-10-16): by reference.** `spigot_trigger(session, name, value)` stores
  `value` under a new id in an environment at `session$userData$.spigot_triggers` (hidden from
  `ls()`; a module's session shares its root's) and sends `spigot:set-input {name, id}`.
  `spigot.js` calls `Shiny.setInputValue("<name>:spigot.ref", id, {priority: "event"})`. The
  `spigot.ref` input handler (`shiny::registerInputHandler()` in `.onLoad`, `force = TRUE`)
  takes the id out of the store and returns the value, so `input[[name]]` is `identical()` to
  `value`: data frames, factors, Dates, `NA`, environments and functions included. The value
  never crosses the websocket, so `spigot_json()` is not involved.
- An id resolves once and only in its own session; an unknown or malformed id gives `NULL`
  (an input handler cannot leave the input unset, and an error there would end the session).
  Ids come from a process-wide counter. Values the page never sends back (tab closed first)
  stay in `userData` until the session ends.
- Every trigger fires the observers, same value or not: Shiny's `input` is a
  `ReactiveValues(dedupe = FALSE)`, and `priority: "event"` skips shiny.js's client-side dedupe in
  `InputNoResendDecorator`. **F22.** (Ids differ anyway, but the handler's output is what Shiny
  stores, so this is still what matters.)
- `name` must match `^[A-Za-z][A-Za-z0-9_.-]*$`, checked before namespacing, so no `:` type
  suffix gets through. With a module's `session`, the name goes through `session$ns()` (the
  module's `input$cart`). `NULL` session → error (unlike `spigot_emit()`); returns
  `invisible(TRUE)`.
- Latency is the M0 step 5 path, unchanged: the e2e test measures fetch start → observer's
  pushed event over 20 sequential runs and checks the median is under 215 ms (5 × the spike's
  p95). Observers run *after* the endpoint returns, and only while the page is open.
- The reactivity vignette draft is `?spigot_trigger` (as M4 used `?spigot_emit`); M7 writes
  the vignette.

## 2026-10-16 — M7: examples

- `live`: a counter shared by every tab. One endpoint uses all three channels: the HTTP reply,
  `spigot_broadcast("count")` to every tab, and `spigot_trigger(s, "clicked")` into the
  caller's server function, which renders a Shiny text output inside the hand-written page
  (`<div id="mine" class="shiny-text-output">`). The page keeps the highest count seen,
  because a push can beat the reply (M0 step 5). Shared state is an environment in `app.R`;
  plumber evaluates `api.R` in `app.R`'s environment, so the endpoints see it.
- `site`: three top-level pages from `pages/`, sharing `head`, `nav` and `footer` partials
  (a partial may hold `</head>`), all `cache = TRUE`. `/cars` is rendered in R with all 32
  `mtcars` rows, then filtered through `GET api/cars`. `POST api/fit` bootstraps a slope in a
  `future::multisession` worker with `future_promise(seed = TRUE)` and returns both PIDs, so
  the test proves the work ran in another process. `future` stays in Suggests; the smoke
  test skips the example without it (`needs` in `test-examples.R`).
- Smoke tests take `(url, headers, session)`; `session` is `open_session()`'s, so pushes and
  triggers are checked without a browser. Each new example also has one chromote test.

## 2026-10-16 — M7: docs and pkgdown

- Vignettes: `why-spigot`, `getting-started` (walks `minimal`, then `site`), `reactivity`
  (the three channels, the `live` example, concurrency), and `client` (the spigot.js
  reference, which until now was only `?spigot_dependency`). Example files are shown with
  knitr's `embed` engine from `system.file("examples", ...)`, so the vignettes cannot drift
  from the shipped examples.
- pkgdown site at `https://kent-orr.github.io/spigot/`, built by `.github/workflows/pkgdown.yaml`
  and deployed to the `gh-pages` branch. "Get started" points at `getting-started` (pkgdown
  only does that by itself for a vignette named after the package).
- PLAN §4.6 `spigot_options(timeout =)` was never built; spigot.js has only the per-call
  `timeout` option, and the docs say so. Deferred: no default timeout in 0.1.0.

## 2026-10-16 — M7: CI and the oldest shiny

- `skip_if_no_chrome()` fails instead of skipping when `SPIGOT_REQUIRE_CHROME=true`, which
  the CI cells that install Chrome for Testing set (PLAN §8, "e2e silently skipped").
- **shiny before 1.11.0 breaks hand-written forms.** Its `initShiny()` treats *any*
  `button[type=submit]` on the page as a `submitButton()`: it calls `preventDefault()` on the
  click, so the form's `submit` event never fires, and it defers every input. Fixed in
  shiny 1.11.0 (#4209: only `.shiny-submit-button`). Found by running the suite against
  shiny 1.8.0: the `minimal` and `site` browser tests fail and `live` (plain buttons) passes.
- shiny's `httpResponse()` adds `X-Content-Type-Options: nosniff` only from 1.14.0 (before
  that, `X-UA-Compatible`). spigot now sets `nosniff` itself on API responses
  (`api_response()` in `rook.R`).
- Full suite (965 expectations, Chrome included) against older shiny in a scratch library:
  1.8.0 and 1.10.0 fail only the `minimal`/`site` browser tests (the submit-button bug above)
  once `nosniff` is spigot's; **1.11.0 passes everything**. `DESCRIPTION` now has
  `shiny (>= 1.11.0)`, and CI has a cell pinned to 1.11.0. F1, F4 and F9 hold back to 1.8.0.

## 2026-10-16 — M8: `/reactlog` is a 404 under spigot

- `page_router()` used to return `NULL` for `/reactlog` and `/reactlog/...` so Shiny's
  reactlog handler could answer. That special case is gone: a spigot app answers
  `/reactlog` with its own 404, like any other unknown path. reactlog is a development
  tool; a user who needs it under spigot can add a page or open an issue.
- Removed with it in the 0.1.1 simplification pass, none user-visible: the `shiny.appobj`
  and `httpHandler` checks in internal `mount_app()` (its only caller passes
  `shiny::shinyApp()`'s result), the idempotency branch in `register_session()` (only
  `wrap_server()` calls it, once per session), and `spigot_app()`'s `missing()` checks
  (R's own "argument is missing" error remains).

## 2026-10-16 — M9: the mount handler does not restore the request (supersedes M1)

- `spigot_mount_handler()` used to put `PATH_INFO` and `SCRIPT_NAME` back after plumber
  answered (`on.exit()` for sync results, `promises::finally()` for async). Shiny's
  `routeHandler` does that because a routed handler may return `NULL` and let the next
  handler see the request. `shiny:::joinHandlers` (checked, 1.14.0) only moves on to the
  next handler on `NULL`.
- spigot's handler never returns `NULL` under the prefix: the guard's denial, `pr$call()`'s
  result and `mount_failure()` are all responses. So nothing reads the request afterwards,
  and the restore is gone. Paths outside the prefix go to the fallback before any rewrite.
- The async-filter test stays: plumber still has to see the stripped path inside an async
  filter, and it does, because nothing puts the prefix back.
- Three test assertions checked the restore and went with it: after a sync call, after an
  async call, and after a sync mount-level failure ("a mount-level failure is a JSON 500").
  PLAN M9 listed only the first two; the third is the same behaviour on the error path, not
  a further change.

## 2026-10-16 — M10: partials are checked once, when the page is created

- `render_whisker()` no longer runs whisker inside `setwd()` to an empty temp directory,
  and no longer turns whisker's "No partial" warning into an error. `check_partial_refs()`
  already rejects any `{{> name}}` not in `partials` when the page is created, with the
  better message; `setwd()` on every request in a server is a global side effect.
- What this gives up: a `{{> name}}` tag after a delimiter change (`{{=<% %>=}}`) is not
  seen by the creation-time scan. Such an unknown partial now gets whisker's default: a
  `name.mustache` file in the working directory if there is one, else a warning and empty
  output. Accepted: the construction check catches every ordinary case.

## 2026-10-21 — Launch modes: `www/` and `R/` are Shiny's, and only for an app directory

- **Found by** a user writing an app from scratch: sourcing `app.R` and running the object
  it returned (an editor's Source button) gave Firefox "blocked due to MIME type
  (text/html)" for `www/app.js`. The script got spigot's HTML 404 page.
- **Cause** (checked, shiny 1.14.0): `runApp("<dir>")`, `runApp("<dir>/app.R")` and
  `shinyAppDir()` all go through `shiny:::shinyAppDir_appR`, which loads `R/` into a
  shared environment, sources `app.R` with `setwd(appDir)`, registers `www/` as an httpuv
  static path at `/`, and sets the working directory to `appDir` in its `onStart`. Running
  the `shiny.appobj` itself (`print.shiny.appobj()` is `runApp(x)`, which is also what the
  console, `source(echo = TRUE)` and `Rscript app.R` do) does none of these.
- **Decision:** no change to spigot. The behaviour is pinned in `test-launch.R` (fixture
  `apps/launch/`) and documented in `?spigot_app` ("Running the app") and the
  getting-started vignette, which point to `runApp("<dir>")`.
- **Considered:** `shinyAppDir_appR` builds its own `staticPaths` and ignores the inner
  app's, so `spigot_app()` could set `app$staticPaths` to serve `www/` in object mode
  without changing directory mode. Not done: the folder would be resolved against the
  working directory when `spigot_app()` is called, which is the guess that failed here, and
  `R/` still would not be loaded, so the app would break one request later. If this
  keeps coming up, the better fix is probably a message when the app starts in object
  mode while a `www/` folder sits in the working directory.

## 2026-10-21 — M11: spigot.js is ES2017 (supersedes the M3 ES5 note)

- **Baseline ES2017**, still no build step. The file already required `fetch`, `URL`,
  `AbortController` and `ReadableStream`, and every browser with those has `class`, arrow
  functions, `const`/`let`, template literals and `async`/`await`. The ES5 rule bought no
  browser and cost a hand-built promise in `request()`, an `Object.create(Error.prototype)`
  constructor, a `withOption()` copy loop and `typeof` guards in `isRawBody()`.
  `SpigotError` is now `class SpigotError extends Error`, so `instanceof Error` still holds.
- **ES2017, not ES2018:** PLAN M11 step 6 wrote `{ ...options, query }`, but object spread
  is ES2018 (EdgeHTML had `AbortController` and `async` but not object spread). The
  shorthand is `Object.assign({}, options, { query })`. Checked by parsing the file with
  acorn at `ecmaVersion: 2017` (passes) and `2016` (fails on `async`).
- **`ReadableStream` is now required.** Dropping the `typeof` guards means `body instanceof
  ReadableStream` throws where it is undefined: Firefox 57-64 had `AbortController` but not
  `ReadableStream`. Accepted (those versions are from 2017-2018); the header comment lists
  it with the other required APIs.
- **Still a classic script in an IIFE.** A module is deferred and sees
  `document.currentScript === null`, which breaks the `data-prefix` read and the guarantee
  that `shiny.js` runs first. The IIFE keeps spigot's names private: a top-level `const` in
  a classic script is a global lexical binding shared with the page's own scripts, and the
  examples declare `const $`.
- `request()` is an `async function`: `Promise.race()` of the timeout and the call, with
  `clearTimeout()` in `finally`. A call that times out while still waiting for
  `spigot.ready` never fetches (it checks `signal.aborted` after the wait), as before.

## 2026-10-21 — M14: `static` and `root`

- **`static` dirs are httpuv static paths**, set in `mount_app()`'s existing on-start
  `later::later()` call, next to the API prefix exclusion (`set_static_paths()`, formerly
  `exclude_static_prefix()`). PLAN M14 step 5 also set `app$staticPaths` for object mode.
  Not needed: `runApp()` calls the app's `onStart` in both launch modes, and the server
  exists by the first event-loop tick in both. Checked: `test-launch.R` serves
  `/static/extra.js` in object mode with only the on-start path. One mechanism, so the two
  modes cannot drift.
- **`root` and the dirs are resolved when `spigot_app()` is called**, to normalized
  absolute paths. In directory mode that is inside Shiny's `setwd(appDir)`, so `root = "."`
  is the app directory; in object mode it is the working directory at the call, as for
  template files. An absolute static dir is used as given.
- **Overlap with the API prefix:** PLAN said a static prefix "equal to or under" the API
  prefix is an error. A static name is one segment, so it can only be equal; the check is
  that the name is not the prefix's first segment, which also refuses `/api` when the
  prefix is `/api/v1` (httpuv would serve `/api/...` files around the API).
- **Added, not in the plan:** a page at or under a static path is an error, with
  `check_pages_vs_prefix()`'s message ("so it would never be served"): httpuv answers
  those paths before R. `spigot_app()` checks pages before `root` and `static`, so an app
  sourced from the wrong directory still reports the missing template first.
- `static = NULL` (the default) sets exactly the paths 0.1.1 set: only the exclusion.

## 2026-10-21 — M15: template search path, partial dirs, pages resolved at build

- **Every `spigot_page()` is resolved when `spigot_app()` builds the app**, by
  `resolve_page(page, loader, partials)`: template and partial files are read, the app's
  partials merged in (the page's win), the `</head>` and partial-reference checks run, and
  `render` built. `spigot_page()` only validates its arguments and records them; `print()`
  says "(unresolved)". PLAN M15 kept text templates rendering at creation. Not done: the
  app's `partials` must reach every page, and a text template using `{{> nav}}` from them
  cannot pass the partial check on its own. One rule instead of two. The errors and their
  messages are the same, and still come before the app runs, from `spigot_app()` instead
  of `spigot_page()`. `resolve_page()` returns a copy, so one page object can serve two
  apps (or, in M16, two blueprints) with different search paths.
- **`as_pages()` stays validation only**; `spigot_app()` resolves the pages after it
  (PLAN said from `as_pages()`). `as_pages(p)` still returns `p` itself.
- **Only the partials a page uses are checked**, following `{{> }}` tags from the template
  through the partials it reaches. In 0.1.1 every partial given to a page was checked, and
  any of them could supply `</head>`. With app-wide partials, one meant for other pages may
  use partials this page lacks, or hold the `</head>` this page does not use. The render-time
  `</head>` check stays.
- **Lookup order** for a file name: each `templates` entry in order (a directory holding
  the name, or a file whose basename is the name), then the name relative to `root` (the
  0.1.1 rule, with `root = "."` the working directory at `spigot_app()`). Absolute names are
  read as given. Every `templates` entry must exist. The miss error keeps 0.1.1's text and
  lists every place it looked in place of "(relative to <wd>)". Page partial file names use
  the same lookup.
- **App `partials`:** `NULL`, a directory (one partial per regular file, named by the file
  name without its last extension; hidden files and subdirectories skipped; two files with
  one name are an error), or a named list exactly like `spigot_page()`'s. PLAN's "a list may
  mix dirs and strings only at the top level" is read as: an unnamed element, such as
  `list("dir")`, is an error, because a list holds partials, not directories.
- `templates = "templates"` is not a default (PLAN M15 step 6).

## 2026-10-21 — M16: blueprints

- **`spigot_blueprint()` validates and records; nothing is read until `spigot_app()`
  builds the app**, the M15 rule. That includes its plumber file: PLAN M16 had `api` parsed
  into a router at creation. Read at build instead, so the file is relative to the app's
  `root` like the blueprint's `templates`, `partials` and `static`. The file is evaluated
  in the environment `spigot_blueprint()` was called from (captured at creation), so in an
  app directory it sees the functions in `R/`. Checked in `test-blueprint.R`.
- **The app's own `api` file is now relative to `root` too.** With `root = "."` that is
  the working directory at `spigot_app()`, exactly as in 0.1.1.
- **Mounting mutates the app's router.** `plumber::pr_mount()` adds each blueprint API to
  the app's `Plumber` object in place. A router passed as `api` therefore gains the mounts.
  Mounts are keyed by path, so building two apps from one router does not stack them.
  Accepted rather than cloning an R6 router.
- **Resolution per blueprint:** `register_blueprints()` records `page$blueprint` on each
  blueprint `spigot_page()`, and `spigot_app()` resolves it with
  `template_loader(c(bp$templates, templates), root)` and
  `merge_partials(app partials, blueprint partials)`, so a page's own partials beat the
  blueprint's, which beat the app's.
- **`{{static}}`** is added by wrapping `data`: a list gets `static` unless it has one; a
  function's result gets it the same way at each request. It is added only when the
  blueprint has `static`. A non-list result is left for the render-time "must return a
  list" error.
- **Blueprint `static` is one directory**, served at `<prefix>/static` through M14's
  `set_static_paths()`; a multi-segment prefix works with httpuv (checked live:
  `/cars/static/cars.js`). Every static path, the app's and the blueprints', is checked
  against every page.
- `check_pages_vs_prefix()` gains `noun`, so a blueprint under the API prefix says
  "The blueprint ...". PLAN M16 step 5's browser test (`spigot.get("cars/fit")`) lives in
  `test-blueprint.R` with the blueprint fixture rather than in `test-client.R`.
- `/shared` is one of Shiny's reserved prefixes, so the fixture's shadowing page is
  `/common`.
