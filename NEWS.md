# spigot 0.1.0

* First release. `spigot_app()` mounts a plumber router inside a Shiny app, so
  hand-written pages (`spigot_page()`) call R endpoints on the same origin and
  port through `spigot.js`.
* API requests are bound to the calling tab's Shiny session (`spigot_session()`).
  By default only open pages of the app can call the API, and cross-origin
  requests are refused.
* `spigot_emit()` and `spigot_broadcast()` push events to pages; `spigot_trigger()`
  sets a Shiny input from an endpoint.
* Three examples: `run_example("minimal")`, `"live"` and `"site"`.
