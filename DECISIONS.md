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
