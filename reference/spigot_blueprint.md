# A blueprint: pages, an API and files that belong together

A blueprint groups the pages of one part of an app with the API
endpoints, templates, partials and static files they use.
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
mounts it under a prefix:
`spigot_app(blueprints = list("/cars" = cars))` serves its page `/` at
`/cars` and its page `/model` at `/cars/model`. Define blueprints in the
app's `R/` directory, which Shiny loads before `app.R`.

## Usage

``` r
spigot_blueprint(
  pages,
  api = NULL,
  templates = NULL,
  partials = NULL,
  static = NULL
)
```

## Arguments

- pages:

  One page, served at the prefix, or a named list of pages keyed by path
  below it, such as `list("/" = list_page, "/model" = model_page)`.

- api:

  `NULL`, the path of a plumber file, or a plumber router. A file is
  read with
  [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md)
  in the environment `spigot_blueprint()` is called from.

- templates:

  Directories or files searched for the blueprint's template files,
  before the app's. See `templates` in
  [`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md).

- partials:

  A directory or a named list of partials, as in
  [`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md).

- static:

  A directory, served at `<prefix>/static`.

## Value

An object of class `spigot_blueprint`, for the `blueprints` argument of
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md).

## Details

Its API is mounted under the app's API prefix: with the default
`prefix`, the blueprint's `/fit` endpoint is `/api/cars/fit`, which a
page calls with `spigot.get("cars/fit")`. The app's session and origin
checks apply to it.

Its template files are looked up in `templates` first, then on the app's
search path. Its `partials` win over the app's, and a page's own over
both. Its `static` directory is served at `<prefix>/static`, and every
blueprint page gets that path, relative to the app root, as `{{static}}`
in its data (`"cars/static"`), so `<script src="{{static}}/cars.js">`
works on any of its pages. A `static` key in a page's own data wins.

Paths are relative to the app's `root` and are read when
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
builds the app, as template files are.

## Examples

``` r
cars <- spigot_blueprint(
  pages = list("/" = spigot_page("list.html"), "/model" = spigot_page("model.html")),
  api = "api/cars.R",
  templates = "templates/cars",
  static = "static/cars"
)
cars
#> <spigot_blueprint>
#>   pages:     /, /model
#>   api:       api/cars.R
#>   templates: templates/cars
#>   static:    static/cars
```
