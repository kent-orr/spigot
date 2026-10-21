# PLAN: spigot 0.1.1 — simplification pass

> The 0.1.0 build plan (M0–M7, 487 lines) is archived:
> `git show v0.1.0:PLAN.md`. DECISIONS.md holds the record of what was
> decided and why; this file holds only what is still to do.

This release changes no user-facing behaviour. It removes code that a
review on 2026-10-16 found to be carrying weight nothing needs:
compatibility shims with no compatibility gain, machinery for states the
code cannot reach, two mechanisms for one rule, and prose that lives in
two places. Where a simplification makes spigot slightly more
permissive, the plan says so and DECISIONS.md gets an entry.

## 1. Ground rules

- **Test-first.** Each step names the test change before the code
  change. Where a behaviour is removed, its test is removed in the same
  commit, never left failing.
- **Behaviour is the spec.** The e2e and integration tests
  (`test-client.R`, `test-push.R`, `test-trigger.R`, `test-page.R`,
  `test-mount.R`) must pass unchanged except where a step below says
  otherwise. A step that needs a test rewritten beyond what is listed
  here has found a behaviour change; stop and record it in DECISIONS.md
  before continuing.
- **`.Rd` files are generated** by `devtools::document()`, never edited
  by hand.
- **One commit per milestone**, suite green with Chrome
  (`skip_if_no_chrome()` must not skip locally) before committing. CI (4
  cells, including shiny 1.11.0) green before M13.
- **Line references** below are to the 0.1.0 sources (`56cf110`). They
  drift as earlier milestones land; the function names are the stable
  anchor.

## 2. Verification, every milestone

``` r

devtools::document()
devtools::test()                        # Chrome installed; no e2e skips
rcmdcheck::rcmdcheck(args = "--no-manual")
```

Expectation count at 0.1.0: 965. It goes **down** in M8–M10 (tests for
removed behaviour) and should otherwise be flat. A rise means a step
added a test that this plan did not call for; that is fine, but note it
in the commit message.

## 3. Milestones

### M8: R internals

Four independent cleanups in `R/`, one commit. None changes a message
that a test matches, except where noted.

**8.1 One scalar check.** `is_string()` lives in `R/page.R:113`; eight
other sites spell it out.

1.  Test: new `test-utils.R` with cases for `is_string()` and
    `is_flag()` (neither has a unit test today; `test-helpers.R` tests
    the test helpers, not `R/utils.R`). `is_string()`: accepts a
    length-1 non-NA character; rejects `NA_character_`, `character(0)`,
    `c("a","b")`, `1`.
2.  Move `is_string()` to `R/utils.R`. Use it at `R/api.R:24`,
    `R/examples.R:41`, `R/mount.R:7` (`check_prefix`), `R/session.R:11`
    (`is_token`), `:98` (`check_event`), `:288` (`spigot_trigger` name),
    `:331` (`resolve_trigger`).
3.  Use `is_flag()` for the `filter` return check at `R/session.R:202`.
4.  [`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
    at `R/session.R:167` checks
    `is.function(session$sendCustomMessage)`;
    [`spigot_trigger()`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md)
    uses `is_session()`. Both use `is_session()`. The error text
    (“`session` must be a Shiny session or NULL.”) stays;
    `test-push.R:45` matches on “session”.

**8.2 Checks for unreachable states.**

1.  `mount_app()` (`R/mount.R:74-81`): delete the `shiny.appobj` and
    `httpHandler` checks. It is internal and only ever receives
    [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html)’s
    result. (Its message also claimed shiny \>= 1.14.0 while DESCRIPTION
    says 1.11.0.) Delete the test `test-mount.R:157` “mount_app() only
    accepts a shiny.appobj with an httpHandler”.
2.  `register_session()` (`R/session.R:19-21`): delete the idempotency
    early return. Only `wrap_server()` calls it, once per session.
    Delete `test-session.R:15` “registering twice is idempotent” and the
    `callbacks()` counter in `helper-session.R` (that test is its only
    reader).
3.  [`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
    (`R/app.R:75-76`): delete the two
    [`missing()`](https://rdrr.io/r/base/missing.html) checks. R’s own
    “argument”pages” is missing, with no default” is enough. No test
    matches them.

**8.3
[`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md).**
`test-push.R:62-235` is the spec and does not change. `except =` and
`filter =` stay; only the implementation shrinks.

1.  Add `live_sessions()` next to `lookup_session()`:
    `as.list(.registry, all.names = TRUE)`, prune any whose `isClosed()`
    is `TRUE`, return the rest unnamed.
2.  Rewrite the body as three
    [`Filter()`](https://rdrr.io/r/base/funprog.html)/[`vapply()`](https://rdrr.io/r/base/lapply.html)
    passes over `live_sessions()`: drop `except` (identity after
    `root_session()`), apply `filter` (every session before any send,
    `is_flag()` on each result, as now), then send with the `tryCatch`
    that prunes on failure. Return `invisible(sum(sent))`.
3.  `prune_session()` is a one-line alias of `unregister_session()`;
    inline it or keep it, but not both names for one thing.
    `test-push.R:235` “prune_session() removes only that session” tests
    the behaviour, so keep whichever name it calls.

**8.4 Small things.**

1.  `page_router()` (`R/page.R:293`): delete the `/reactlog` special
    case and the test `test-page.R:220`. A spigot app answers
    `/reactlog` with its own 404. **DECISIONS entry:** reactlog is a
    development tool; a user who needs it under spigot can add a page or
    open an issue.
2.  `strsplit_first()` (`R/page.R:242`):
    `sub("^/([^/]*).*$", "\\1", path)`.
3.  `base_href()` (`R/page.R:247`):
    `lengths(strsplit(path, "/", fixed = TRUE)) - 2L` is the depth
    (`"/"` gives `-1`, `"/docs/intro"` gives `1`). The existing tests at
    `test-page.R:276-310` cover every depth.
4.  `spigot_serializer()` (`R/api.R:36`): pass `spigot_json` itself, not
    `function(val) spigot_json(val)`.

### M9: Mount handler without path restore

**Why.** `spigot_mount_handler()` (`R/mount.R:36-61`) restores
`PATH_INFO` and `SCRIPT_NAME` after plumber answers: `on.exit` for sync
results,
[`promises::finally()`](https://rstudio.github.io/promises/reference/then.html)
for async, with an `async` flag to pick one. Shiny’s `routeHandler` does
the same because a routed handler may return `NULL` and let the next
handler see the request. `shiny:::joinHandlers` (checked, 1.14.0) only
moves to the next handler on `NULL`. After the rewrite, spigot’s handler
never returns `NULL`: the guard, `pr$call()` and `mount_failure()` all
return a response. Nothing reads the request afterwards.

1.  Tests, `test-mount.R`:
    - `:32` “the prefix moves from PATH_INFO to SCRIPT_NAME, then is
      restored”: drop the two `expect_identical(req$...)` lines after
      the call; rename to “…to SCRIPT_NAME”.
    - `:101` “async endpoints return a promise of an httpResponse”: drop
      the final `expect_identical(req$PATH_INFO, "/api/async")`.
    - `:113` “the prefix stays stripped until an async filter has
      finished routing”: keep. It now asserts that plumber sees the
      stripped path inside an async filter, which is still worth
      pinning.
    - `:41` “non-prefix paths fall through untouched”: keep unchanged.
      The fallback runs before any rewrite.
2.  Code: delete `old_script`, `restore()`, `async`, the `on.exit`, and
    the `promises::finally(restore)` link. The handler becomes: match
    prefix or fall back; rewrite `SCRIPT_NAME`/`PATH_INFO`; run guard;
    `pr$call(req)`; convert sync, or
    `then(rook_to_httpResponse) |> catch(mount_failure)` for a promise;
    the outer `tryCatch(error = mount_failure)` stays.
3.  **DECISIONS entry** with the `joinHandlers` reasoning above, so the
    M1 entry’s “restored when the request finishes” is visibly
    superseded.

### M10: Partials are checked once

**Why.** `check_partial_refs()` (`R/page.R:161`) errors at construction
for any `{{> name}}` not in `partials`. `render_whisker()`
(`R/page.R:178`) then also runs every render inside
[`setwd()`](https://rdrr.io/r/base/getwd.html) to an empty temp
directory and promotes whisker’s “No partial” warning to an error. The
only case the second adds is a tag after a `{{=<% %>=}}` delimiter
change. [`setwd()`](https://rdrr.io/r/base/getwd.html) per request in a
server is a global side effect, and the construction check is the one
that gives the better error anyway.

1.  Tests, `test-page.R`:
    - `:143` “a partial the template uses but nobody supplied is an
      error at creation”: keep. This is the surviving rule.
    - `:151` “a missing partial at render is an error, not a file
      lookup”: delete. It writes `nav.mustache` to disk to prove the
      render-time guard; that guard goes.
    - `:115` “cache = TRUE renders once”: mocks `render_whisker`, so the
      function must keep its name and signature.
2.  Code: `render_whisker()` becomes
    `whisker::whisker.render(template, data = data, partials = partials)`.
    Delete `empty_dir()` and `in_dir()`.
3.  Docs:
    [`?spigot_page`](https://kent-orr.github.io/spigot/reference/spigot_page.md)
    Templates section says a missing partial “is an error (spigot does
    not look for whisker’s `name.mustache` files)”. Make it “is an error
    when the page is created”.
4.  **DECISIONS entry:** after a delimiter change, an unknown partial
    falls back to whisker’s default (a `.mustache` lookup in the working
    directory, else a warning and empty output). Accepted: the
    construction check catches every ordinary case.

### M11: spigot.js in current JavaScript

**Why.** The file header says ES5 syntax, no build step. It also
requires `fetch`, `Promise`, `URL` and `AbortController`. No browser has
those and lacks `class`, arrow functions, `const`/`let`, template
literals, spread or `async`/`await`. The ES5 rule buys nothing and costs
the hand-built promise in `request()`, the
`Object.create(Error.prototype)` constructor, `withOption()`, and the
`typeof X !== "undefined"` guards in `isRawBody()`.

The e2e tests are the spec and do not change: `test-client.R:71-278`,
`test-push.R:373-493`, `test-trigger.R`, and the browser tests in
`test-page.R` and `test-examples.R`. Run them before and after.

1.  Baseline: ES2017 (the year `async`/`await` shipped everywhere
    `AbortController` did). Say so in the header comment, replacing the
    ES5 sentence. Still no build step; still served as is.
2.  Keep the IIFE and `"use strict"`. A top-level `const` in a classic
    script is a global lexical binding shared with the page’s own
    scripts, and the examples declare `const $`. The IIFE is what keeps
    spigot’s names private.
3.  Keep it a **classic** script, not `type="module"`. A module is
    deferred and sees `document.currentScript === null`, which would
    break the `data-prefix` read at line 12 and the load-order guarantee
    that `shiny.js` runs first.
4.  `SpigotError`: `class SpigotError extends Error` with `name`,
    `status`, `body` set in the constructor. `test-client.R:202` checks
    `instanceof spigot.SpigotError`, `.status`, `.message`, `.body`;
    `instanceof Error` must still hold.
5.  `request()`: an `async function`. Build `init` as now; wrap the body
    in `Promise.race([timeout, run()])` where `timeout` rejects with the
    status-0 `SpigotError` after `options.timeout` ms and aborts the
    controller, and `run()` awaits `spigot.ready`, sets the session
    header last, fetches and reads the body, mapping a non-`SpigotError`
    rejection to the status-0 “network error” form. `clearTimeout` in a
    `finally`. The semantics tested at `test-client.R:135` (waits for
    `ready`), `:225` (timeout counts from the call, `signal.aborted`),
    `:241` (network failure) and `:250` (header cannot be overridden)
    stay.
6.  `withOption()` becomes `{ ...options, query }` /
    `{ ...options, body }` (only when the value is not `undefined`, as
    now).
7.  `isRawBody()`: drop the `typeof` guards; plain `instanceof` chain.
8.  Everything else (`encodeQuery`, `apiUrl`, `readBody`, listeners,
    `dispatch`, handlers, `onFragmentClick`) is a mechanical conversion
    to `const`/`let`, arrows and template literals. Do not change logic
    while converting.
9.  Docs: neither `vignettes/client.Rmd` nor
    [`?spigot_dependency`](https://kent-orr.github.io/spigot/reference/spigot_dependency.md)
    mentions ES5. `client.Rmd:11` says “plain JavaScript with no build
    step”, which stays true. Only the header comment of `spigot.js`
    changes.
10. **DECISIONS entry:** ES2017 baseline and why; classic script and
    IIFE kept, with the two reasons above.

### M12: Help pages are reference, vignettes are narrative

**Why.**
[`?spigot_dependency`](https://kent-orr.github.io/spigot/reference/spigot_dependency.md)
documents the whole JavaScript API; `vignettes/client.Rmd` does it
again.
[`?spigot_emit`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
and
[`?spigot_trigger`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md)
were written as the drafts of `vignettes/reactivity.Rmd` (DECISIONS, M4
and M6) and still read like it. Two copies to keep in sync on every
behaviour change.

Rule for each page: keep the first paragraph (what it is, when to call
it), every `@param`, `@return`, `@examples`, and any sentence that
states a **contract** (shapes, ordering guarantees, what errors). Move
or delete **explanation** (how it works internally, design rationale,
alternatives) if the vignette already has it; if the vignette does not,
move it there, do not delete it.

1.  Before editing, diff each page against its vignette section and list
    the sentences only the help page has. Those move to the vignette
    first.
    - [`?spigot_dependency`](https://kent-orr.github.io/spigot/reference/spigot_dependency.md)
      ↔︎ `client.Rmd` “Calling the API”, “Errors”, “The session”, “Events
      from R”, “Links on nested pages”.
    - [`?spigot_emit`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
      ↔︎ `reactivity.Rmd` “Push” (the chat-room example is already
      there).
    - [`?spigot_trigger`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md)
      ↔︎ `reactivity.Rmd` “The bridge”.
2.  [`?spigot_dependency`](https://kent-orr.github.io/spigot/reference/spigot_dependency.md):
    the bulleted JS API list and the paths/bodies paragraph become one
    paragraph naming `spigot.get()`, `spigot.post()`, `spigot.on()` and
    `SpigotError`, then
    [`vignette("client", package = "spigot")`](https://kent-orr.github.io/spigot/articles/client.md).
    Keep the `prefix` param, the `data-prefix` mechanism (that is the
    contract), and the example.
3.  [`?spigot_emit`](https://kent-orr.github.io/spigot/reference/spigot_emit.md):
    keep the one-tab/all-tabs sentence, the
    [`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md)
    shape sentence, and the “an event can reach the page before the HTTP
    response” sentence (contract). Delete the `future` worker paragraph
    and the “no replay” sentence; `reactivity.Rmd:78-87` already has
    both. Keep the two examples.
4.  [`?spigot_trigger`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md):
    keep the first paragraph, the “value never leaves R, input is
    [`identical()`](https://rdrr.io/r/base/identical.html)” sentence
    (contract), the “fires every time, even with the same value”
    sentence (contract), and the namespacing sentence.
    `reactivity.Rmd:90-123` (“The bridge”) already explains the id swap,
    the extra websocket trip, running after the endpoint returns, and
    every-trigger-fires. Delete those paragraphs from the page; only
    `priority: "event"` is named nowhere else, and it is an
    implementation detail, so it goes too.
5.  [`?spigot_app`](https://kent-orr.github.io/spigot/reference/spigot_app.md):
    out of scope for this pass; its five sections are mostly contract.
    Revisit if M12 goes well.
6.  `devtools::document()`; `rcmdcheck` must show no Rd cross-reference
    warnings;
    [`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)
    locally and read the three pages and two articles once.

### M13: Release 0.1.1

1.  `NEWS.md`: one entry. “Internal simplification; no change to
    behaviour. spigot.js now uses current JavaScript syntax (ES2017),
    same browser support. A `{{> name}}` partial missing from `partials`
    is caught when the page is created.” Mention the `/reactlog` 404 in
    one clause.
2.  `DESCRIPTION` version 0.1.1.
3.  Full suite with Chrome locally; push; all 4 CI cells green,
    including the shiny 1.11.0 cell (the ES2017 change has nothing to do
    with shiny, but the e2e tests there are the broadest browser check
    we have).
4.  `pkgdown` workflow green; site shows the trimmed pages.
5.  Tag `v0.1.1`.

## 4. Deliberately not in this pass

- `spigot_broadcast(except =)` could be expressed with `filter =` and
  dropped (~20 lines with `check_except()` and `root_session()`). It is
  public API; removing it is a 0.2.0 question, not a cleanup.
- [`run_example()`](https://kent-orr.github.io/spigot/reference/run_example.md)’s
  three functions could collapse onto
  [`match.arg()`](https://rdrr.io/r/base/match.arg.html). Harmless as
  is.
- `helper-proxy.R` (85 lines, 3 tests) is the heaviest test
  infrastructure for the least verified payoff (DECISIONS, M2 and M3:
  real deployments unchecked). Keep until a real Shiny Server or Connect
  deployment either confirms or replaces it.
- The `looks_like_text()` template-or-path heuristic, the
  [`later::later()`](https://later.r-lib.org/reference/later.html)
  static-path exclusion, the `</head>` split, by-reference
  [`spigot_trigger()`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md),
  and the `<base href>` plus fragment-click handler all have recorded
  reasons and stay.

## 5. Next release: 0.2.0 — a Flask-shaped surface (M14–M17)

Design conversation 2026-10-21. spigot was written to give a Flask +
Jinja development flow on a Shiny Server platform. 0.1.x has the pieces
(pages, whisker templates, partials, a plumber API, `www/`) but not the
shape: no blueprint, no template search path, no static dirs beyond
`www/`, every file path relative to the working directory. 0.2.0 adds
that shape **additively**: every new argument defaults to 0.1.1
behaviour, the three examples and `apps/launch/` run unchanged until M17
rewrites one of them to show the new surface.

Target surface, so the milestones below have something to point at:

``` r

# app.R
spigot_app(
  pages      = list("/" = spigot_page("index.html")),
  api        = "api.R",
  blueprints = list("/cars" = cars, "/model" = model),   # objects from R/
  templates  = "templates",            # search path: dirs and/or files
  partials   = "templates/partials",   # a dir: one partial per file, keyed by stem
  static     = "static",               # served at /static; named list for several
  root       = "."                     # what the paths above resolve against
)

# R/cars.R
cars <- spigot_blueprint(
  pages     = list("/" = spigot_page("list.html"), "/model" = spigot_page("model.html")),
  api       = "api/cars.R",            # mounted at /api/cars
  templates = "templates/cars",        # searched before the app's
  partials  = "templates/cars/partials",
  static    = "static/cars"            # served at /cars/static
)
```

Decisions taken in the design conversation, to be entered in
DECISIONS.md as each milestone lands (the “why” belongs there, not
here):

- **Paths resolve against `root`** at construction, and `root` defaults
  to the working directory then. In directory mode that is the app
  directory (DECISIONS, 2026-10-21 launch modes); in object mode it is
  whatever it is, as for templates today.
- **Static dirs are served by httpuv**, not R. `addResourcePath()` takes
  one segment, but `server$setStaticPath()` takes any prefix, and
  `mount_app()` already calls it at start. Directory mode: set the paths
  in the existing on-start hook. Object mode: `app$staticPaths`, which
  `runApp(<appobj>)` honours (the “considered” option of the
  launch-modes decision, now with `root` to make it right).
- **No filename-only static references.** `src="cars.js"` would need
  every static dir root-mounted, which Shiny owns in directory mode, so
  spigot would serve files from R after a page miss and file names would
  collide with page paths. Instead `src="static/app.js"` resolves at any
  depth via the `<base href>`, and a blueprint page gets `{{static}}` in
  its data (`"cars/static"`) so its template needs no knowledge of its
  prefix. whisker has no lambdas (checked: a function as a section value
  renders empty), so a Flask `url_for` helper is not possible; a
  variable is.
- **A blueprint’s API mounts under the app prefix**, `/api/<name>/...`,
  with
  [`plumber::pr_mount()`](https://www.rplumber.io/reference/pr_mount.html).
  One guard, one prefix for spigot.js, `check_pages_vs_prefix()`
  unchanged; the client calls `spigot.get("cars/fit")`. Flask’s
  `/cars/api/...` was considered and rejected for those three reasons.
- **Template files are read when the app is built**, not when
  [`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)
  is called, because a name can only be resolved once the page knows its
  blueprint and the app’s search path. Still before the app runs; the
  “can’t find” error keeps its text and gains the search path it tried.
- **`www/` and `R/` stay Shiny’s.** `static` is in addition to `www/`,
  never a replacement. Blueprints live in `R/` because Shiny loads it;
  spigot adds no loader.

Open, defaults chosen for this plan: dynamic segments (`/cars/<id>`) are
**not** in 0.2.0; `data = function(req)` reads the query string, and
converters are a 0.3.0 question.

Ground rules of §1 apply. Line references are to the 0.1.1 sources once
M13 is tagged. Expectation count goes **up** in every milestone; note
the number in each commit message.

### M14: `root` and `static`

**Why.** Independent of templates and blueprints, and testable against
the `apps/launch/` fixture and `test-launch.R` already in place for the
launch-modes decision. Lands the httpuv static-path mechanism that
blueprints reuse.

1.  Test, `test-launch.R`: add `static/extra.js` to `apps/launch/` and a
    `static =` argument to its `app.R`. Directory mode (all three
    existing launch tests) and object mode serve `/static/extra.js` with
    a JavaScript content type. `www/app.js` keeps its existing
    expectations in both modes (404 in object mode: unchanged).
2.  Test, new `test-static.R` (unit, no server): `check_static()`
    accepts a string (prefix `/static`), a named list (prefix `/<name>`
    each), rejects an unnamed list of two, a name with a slash, a name
    in `reserved_prefixes`, a dir that does not exist (error names
    `root`), and a prefix equal to or under the API `prefix`.
3.  Test, `test-static.R`: `resolve_root()` with `root = "."` returns
    the normalized working directory; with a relative `root` resolves it
    against the working directory; errors when the dir does not exist.
4.  Code, new `R/static.R`: `check_static()`, `resolve_root()`,
    `static_paths()` returning a named list of normalized dirs keyed by
    URL prefix.
5.  Code, `R/mount.R`: `mount_app()` gains `static = list()`. Directory
    mode: the existing on-start
    [`later::later()`](https://later.r-lib.org/reference/later.html)
    call also sets the static paths. Object mode: `app$staticPaths` is
    set from the same list. Both from one helper so the two modes cannot
    drift.
6.  Code, `R/app.R`: `spigot_app(static = NULL, root = ".")`. `NULL` is
    0.1.1 behaviour exactly. Help: a “Files” section replacing the
    `www/` sentence in “Running the app”.
7.  Test, `test-page.R`: a page at `/docs/intro` whose template has
    `<script src="static/a.js">` loads it (the `<base href>` already
    does this; the test pins that `static` and nested pages compose).

### M15: template search path and partial dirs

**Why.** `spigot_page("index.html")` should mean “the template named
index.html”, not “the file at ./index.html”, once the app says where
templates are. Blueprints need the loader to exist before they can put
their own dir in front of it.

1.  Test, new `test-templates.R`: `template_loader(dirs, root)` finds
    `a.html` in the second dir when the first lacks it; the first dir
    wins on a tie; a single file in `templates =` is found by basename;
    a name that is a path relative to `root` still resolves last (0.1.1
    compatibility); the error for a miss lists the dirs tried.
2.  Test, `test-templates.R`: `partials = "<dir>"` yields one partial
    per file keyed by the filename without extension; a dir with
    `nav.html` and `nav.mustache` is an error (duplicate key); a named
    list is unchanged; a list may mix dirs and strings only at the top
    level (`list(nav = "x.html")`, not `list("dir")`).
3.  Test, `test-page.R`: `spigot_page("missing.html")` no longer errors
    at creation; `spigot_app(pages = spigot_page("missing.html"))`
    errors with the 0.1.1 message plus the search path. Move the
    existing “can’t find” expectations accordingly. Text templates
    (`looks_like_text()`) are untouched and still render at creation.
4.  Code, `R/page.R`:
    [`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)
    keeps the template string unresolved when it is a path; `render` is
    built by a new `resolve_page(page, loader, partials)` called from
    `as_pages()`. `print.spigot_page()` shows “unresolved” until then.
    The `</head>` and partial-reference checks (M10) move to
    `resolve_page()`, same messages.
5.  Code, new `R/templates.R`: `template_loader()`,
    `read_partials_dir()`, `merge_partials(app, page)` (page-level
    `partials` win over app-level).
6.  Code, `R/app.R`: `spigot_app(templates = NULL, partials = NULL)`.
    `NULL` is 0.1.1 behaviour. `templates = "templates"` is **not** the
    default: a default that depends on whether a dir exists is the kind
    of guess the launch-modes decision warns about. The vignette shows
    the one-line opt-in.

### M16: blueprints

**Why.** The point of the release. Built on M14 (per-blueprint static
prefix) and M15 (per-blueprint loader and partials).

1.  Test, new `test-blueprint.R` (unit): `spigot_blueprint()` returns a
    `spigot_blueprint` with `pages`, `api` (a `Plumber`, from a file or
    router or `NULL`), `templates`, `partials`, `static`; rejects a page
    path that is not a page path, an `api` that is neither;
    [`print()`](https://rdrr.io/r/base/print.html) lists pages and
    whether it has an API.
2.  Test, `test-blueprint.R`:
    `register_blueprints(app_pages, blueprints, prefix)` returns the
    merged page list with `/cars` + `/` = `/cars`, `/cars` + `/model` =
    `/cars/model`; a collision with an app page or another blueprint is
    an error naming both; a blueprint prefix under the API `prefix` is
    an error (reuse `check_pages_vs_prefix()`); `/` is not a valid
    blueprint prefix.
3.  Test, `test-blueprint.R`: a blueprint page’s `data` gains
    `static = "cars/static"` when the blueprint has `static`, and
    nothing otherwise; a function `data` gets it added to its result; a
    user key `static` wins (documented, not an error).
4.  Test, `test-blueprint.R` (server, `helper-server.R`): an app with
    one blueprint serves `/cars`, `/cars/model`, `/cars/static/cars.js`,
    and `/api/cars/fit`; the session guard applies to `/api/cars/fit`
    (401 without a token); the blueprint’s templates dir shadows the
    app’s for a same-named template; the blueprint’s partial `nav`
    shadows the app’s.
5.  Test, `test-client.R`: `spigot.get("cars/fit")` reaches the mounted
    router (one e2e case; the prefix handling in spigot.js is unchanged,
    this pins that).
6.  Code, new `R/blueprint.R`: `spigot_blueprint()`,
    `print.spigot_blueprint()`, `register_blueprints()`. API mounting:
    `plumber::pr_mount(app_pr, "/<name>", bp_pr)` where `<name>` is the
    blueprint prefix without its slash;
    [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md)
    builds the blueprint router so it gets
    [`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md).
    Static: each blueprint’s dir is added to the M14 list under
    `<prefix>/static`.
7.  Code, `R/app.R`: `spigot_app(blueprints = NULL)`; `as_pages()` runs
    after `register_blueprints()`, so every existing path check applies
    to the merged list. Help: a “Blueprints” section;
    `?spigot_blueprint` is reference only (M12 rule).

### M17: example, vignette, release 0.2.0

1.  Rewrite `inst/examples/site/` onto the new surface: `templates/`,
    `static/`, the `/cars` and `/model` pages as two blueprints in `R/`,
    `www/` gone from it. The `test-examples.R` expectations for `site`
    change only in the URLs of its script files; the page content
    expectations stay. `minimal` and `live` are left on the 0.1.1
    surface on purpose, so both ways are exercised.
2.  New vignette `flask-flow.Rmd`: the project layout, one blueprint,
    what `root` means under each launch mode. Narrative only (M12 rule);
    the help pages hold the argument details.
3.  `NEWS.md` 0.2.0: blueprints, template search path, partial dirs,
    static dirs, `root`; “template files are now read when the app is
    built”. No breaking change.
4.  `DESCRIPTION` 0.2.0; full suite with Chrome; 4 CI cells green;
    pkgdown green; tag `v0.2.0`.

### Deliberately not in 0.2.0

- Dynamic path segments and converters (`/cars/<id>`). Needs a routing
  change in `page_router()` and a decision on how matched values reach
  `data`; 0.3.0.
- A `url_for`-style helper in templates. Not possible in whisker without
  lambdas; `{{static}}` and the `<base href>` cover the cases found so
  far.
- Serving static files from R so a bare filename works. Rejected above.
- A default `templates = "templates"`. Rejected above; revisit if the
  one-line opt-in turns out to be what every app writes.
