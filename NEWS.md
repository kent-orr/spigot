# spigot 0.2.0

* Blueprints: `spigot_blueprint()` groups a section's pages, API, templates, partials
  and static files, and `spigot_app(blueprints = list("/cars" = cars))` serves its pages
  under `/cars`, its API under `/api/cars` and its static files at `/cars/static`, which
  its pages see as `{{static}}`. `vignette("blueprints")` explains them and
  `vignette("flask-flow")` shows the folder layout.
* `spigot_app(templates =)` is a search path for template files, and
  `spigot_app(partials =)` gives every page shared partials: a folder (one partial per
  file) or a named list. A page's own partials win.
* `spigot_app(static =)` serves folders at `/static` (or `/<name>` each) in every launch
  mode, not only when the app folder is run, as `www/` is.
* `spigot_app(root =)` is the folder that these paths, and the `api` file, are relative
  to. It defaults to the working directory, as in 0.1.x.
* Template files are now read, and their checks run, when `spigot_app()` builds the app
  rather than when `spigot_page()` is called. The errors are the same, and a missing
  file's error now lists every place spigot looked. Only the partials a page uses are
  checked.
* The `site` example is now laid out with `templates/`, `static/` and two blueprints.
  The `live` example no longer shows a stale tab count when its first reply arrives late.
* No breaking changes: every new argument defaults to 0.1.1 behaviour.

# spigot 0.1.1

* Internal simplification; no change to behaviour, except that `/reactlog` now gets
  the app's own 404 instead of Shiny's reactlog. `spigot.js` now uses current
  JavaScript syntax (ES2017) and needs `fetch`, `AbortController` and
  `ReadableStream`, which every current browser has. A `{{> name}}` partial missing
  from `partials` is caught when the page is created.

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
