# Templates, static files and blueprints

A small spigot app is a folder with `app.R`, a template or two and a
`www/` folder. Once an app has several sections, the files are easier to
find in the layout a Flask developer would expect: templates in
`templates/`, scripts and stylesheets in `static/`, and each section of
the site in a *blueprint* that keeps its pages, endpoints, templates and
files together. This vignette shows that layout. Every part of it is
optional, and an app without it works as before.

## The layout

    myapp/
    ├── app.R
    ├── api.R               # the app's own endpoints
    ├── R/
    │   └── cars.R          # the cars blueprint
    ├── api/
    │   └── cars.R          # the cars endpoints
    ├── templates/
    │   ├── index.html
    │   ├── partials/
    │   │   └── nav.html
    │   └── cars/
    │       ├── list.html
    │       └── model.html
    └── static/
        ├── site.css
        └── cars/
            └── cars.js

`app.R` says where things are:

``` r

spigot_app(
  pages      = list("/" = spigot_page("index.html")),
  api        = "api.R",
  blueprints = list("/cars" = cars),
  templates  = "templates",
  partials   = "templates/partials",
  static     = "static"
)
```

**`templates`** is a search path. With it, `spigot_page("index.html")`
names a template rather than a file next to `app.R`: spigot looks for
`templates/index.html`, and only then for `index.html` in the app’s
folder. It can list several folders, searched in order.

**`partials`** is a folder of partials every page can use, one per file:
`nav.html` is `{{> nav}}`. A page’s own `partials` win over these, so
one page can swap in its own nav.

**`static`** is a folder served at `/static`. Every page can load
`<link rel="stylesheet" href="static/site.css">`, whatever its depth,
because spigot gives nested pages a `<base href>` that points at the
app’s root. httpuv serves these files directly, without running R.
`www/` keeps working alongside `static/`. Unlike `www/`, `static/` is
served however the app is launched (see [Where paths start](#root)).

## A blueprint

The cars section of the site is one blueprint, defined in `R/cars.R`:

``` r

cars <- spigot_blueprint(
  pages     = list("/" = spigot_page("list.html"), "/model" = spigot_page("model.html")),
  api       = "api/cars.R",
  templates = "templates/cars",
  partials  = "templates/cars/partials",
  static    = "static/cars"
)
```

`spigot_app(blueprints = list("/cars" = cars))` mounts it at `/cars`:

- Its pages are served under the prefix: `/` at `/cars`, `/model` at
  `/cars/model`. They are checked like the app’s own pages, so a path
  served twice is an error when the app is built.
- Its endpoints are served under the app’s API, at `/api/cars/...`,
  behind the same session check. A page calls them with
  `spigot.get("cars/fit")`.
- Its templates are looked for in `templates/cars/` first, then on the
  app’s search path, so the blueprint can override a shared template.
  Its partials win over the app’s, the same way.
- Its static files are served at `/cars/static`, and each of its pages
  gets that path as `{{static}}`. The template does not need to know
  where the blueprint is mounted:

``` html
<script src="{{static}}/cars.js"></script>
```

``` r

# api/cars.R
#* @get /fit
function(x = "wt") {
  fit_cars(x)    # defined in R/, so available to the endpoints too
}
```

Blueprints live in `R/` because Shiny loads every file there before it
runs `app.R`, so `cars` exists by the time
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
needs it, and functions defined in `R/` are available to the endpoints.
spigot adds no loader of its own. The
[Blueprints](https://kent-orr.github.io/spigot/articles/blueprints.md)
vignette covers them in full.

### Compared with Flask

| Flask | spigot |
|----|----|
| `Blueprint("cars", ...)`, `url_prefix="/cars"` | `spigot_blueprint(...)`, `blueprints = list("/cars" = cars)` |
| `render_template("list.html")` | `spigot_page("list.html")` |
| `url_for("cars.static", filename="cars.js")` | `{{static}}/cars.js` |
| a blueprint’s routes under `/cars/...` | its endpoints under `/api/cars/...` |
| `<int:id>` in a route | not yet: a page reads the query string with `data = function(req)` |

whisker, spigot’s template engine, has no functions, so there is no
`url_for()`. Relative URLs and `{{static}}` cover what it is used for.

## Where paths start: `root`

Every path in
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
and
[`spigot_blueprint()`](https://kent-orr.github.io/spigot/reference/spigot_blueprint.md)
(templates, partials, static folders, plumber files) is relative to
`root`, and the files are read when
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
builds the app. `root` defaults to the working directory at that moment.
How the app is launched decides what that is (see “Running the app” in
[`?spigot_app`](https://kent-orr.github.io/spigot/reference/spigot_app.md)):

- **Running the folder**, with `shiny::runApp("myapp")`, RStudio’s Run
  App button, Shiny Server or Posit Connect: Shiny loads `R/`, then runs
  `app.R` with the folder as the working directory. `root` is the app’s
  folder, and everything above works.
- **Running the app object**, by printing what `app.R` returns (at the
  console, sourcing it with echo, or `Rscript app.R`): Shiny does
  neither. The paths are relative to wherever R happens to be, and `R/`
  is not loaded, so `cars` does not exist and `app.R` stops with an
  error. Run the folder instead: `Rscript -e 'shiny::runApp("myapp")'`.

`root` can be set to an absolute path, for an app whose files live
somewhere other than the working directory. That does not load `R/`;
only running the folder does.
