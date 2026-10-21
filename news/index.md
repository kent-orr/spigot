# Changelog

## spigot 0.1.1

- Internal simplification; no change to behaviour, except that
  `/reactlog` now gets the app’s own 404 instead of Shiny’s reactlog.
  `spigot.js` now uses current JavaScript syntax (ES2017) and needs
  `fetch`, `AbortController` and `ReadableStream`, which every current
  browser has. A `{{> name}}` partial missing from `partials` is caught
  when the page is created.

## spigot 0.1.0

- First release.
  [`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
  mounts a plumber router inside a Shiny app, so hand-written pages
  ([`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md))
  call R endpoints on the same origin and port through `spigot.js`.
- API requests are bound to the calling tab’s Shiny session
  ([`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md)).
  By default only open pages of the app can call the API, and
  cross-origin requests are refused.
- [`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  and
  [`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  push events to pages;
  [`spigot_trigger()`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md)
  sets a Shiny input from an endpoint.
- Three examples: `run_example("minimal")`, `"live"` and `"site"`.
