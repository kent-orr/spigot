# Blueprints

A blueprint is one section of a spigot app, packaged so that it can be
written, read and moved on its own. It holds the section’s pages and
whatever they need: the endpoints they call, their templates and
partials, and the scripts and stylesheets they load.
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
mounts it under a prefix, and the blueprint itself never says where that
is.

Use one when an app has sections that are more than a page each, such as
a cars section with a table and a model form, or an admin area, so that
`app.R` lists sections rather than every page and endpoint. A one-page
app does not need one. The [Templates, static files and
blueprints](https://kent-orr.github.io/spigot/articles/flask-flow.md)
vignette shows the folder layout around them. This one covers what a
blueprint is and how its parts are found.

``` r

library(spigot)
```

## A blueprint and where it lands

Here is a small blueprint with two pages and one endpoint. The templates
are inline text to keep the example short. A real one usually names
template files.

``` r

page <- function(body) {
  spigot_page(paste0("<html><head></head><body>", body, "</body></html>"))
}

greet <- spigot_blueprint(
  pages = list(
    "/"      = page("<h1>Hello</h1> <a href='greet/about'>About</a>"),
    "/about" = page("<p>A section of the app.</p>")
  ),
  api = spigot_api() |> plumber::pr_get("/hello", function(name = "you") {
    list(message = paste("Hello,", name))
  })
)
greet
#> <spigot_blueprint>
#>   pages:     /, /about
#>   api:       router
```

Its paths are written as if it were the whole app: its main page is `/`.
The app chooses the prefix when it mounts it:

``` r

app <- spigot_app(
  pages = page("<a href='greet'>Greetings</a>"),
  api = spigot_api(),
  blueprints = list("/greet" = greet)
)
```

Each part of a blueprint mounted at `/greet` lands here:

| Part | In the blueprint | Served at | From one of its pages |
|----|----|----|----|
| A page | `/` | `/greet` | `<a href="greet">` |
| A page | `/about` | `/greet/about` | `<a href="greet/about">` |
| An endpoint | `/hello` | `/api/greet/hello` | `spigot.get("greet/hello")` |
| A static file | `hello.js` in `static` | `/greet/static/hello.js` | `<script src="{{static}}/hello.js">` |

Links on a spigot page are relative to the app’s root, whatever the
page’s depth, because spigot gives nested pages a `<base href>` that
points there. That is why the links above start with `greet/` and not
`/greet/`: the same page works when the app itself is served under a
path, as it is on Shiny Server or Posit Connect. A page that should not
depend on the blueprint’s own prefix can use `{{static}}` for its files
(see below). Its links and API calls still name the prefix.

The prefix can have more than one segment, such as `"/tools/greet"`. It
cannot be `/`, and it cannot be under the API’s prefix.

## Pages

A blueprint’s `pages` are the same as
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)’s:
one page, served at the prefix, or a list of pages named by path. Every
page must be a
[`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md),
because a Shiny UI can only be the app’s own `/` page. Data, data
functions, caching and partials work as on the app’s pages.

When the app is built, spigot checks a blueprint’s pages along with the
app’s own. A path that both the app and a blueprint serve is an error
that names both:

``` r

spigot_app(
  pages = list("/" = page("home"), "/greet/about" = page("mine")),
  api = spigot_api(),
  blueprints = list("/greet" = greet)
)
#> Error:
#> ! The page "/greet/about" of the blueprint "/greet" is also a page of the app.
```

So is a blueprint mounted under the API:

``` r

spigot_app(pages = page("home"), api = spigot_api(), blueprints = list("/api/greet" = greet))
#> Error:
#> ! The blueprint "/api/greet" is under the API prefix "/api", so it would never be served.
```

## The API

A blueprint’s `api` is a plumber file or a plumber router. spigot mounts
it on the app’s router at the blueprint’s prefix, so with the default
`prefix = "/api"` the blueprint’s `/hello` is `/api/greet/hello`. It is
part of the app’s API, so the app’s checks apply: unless
`require_session = FALSE`, it answers only requests from the app’s own
pages, and its endpoints can call
[`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md),
[`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
and the rest. A page calls it like any other endpoint, with the path
below the API prefix:

``` js
const reply = await spigot.get("greet/hello", { name: "Ada" });
```

A file is read when
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
builds the app, relative to the app’s `root`, and its endpoints are
evaluated in the environment where
[`spigot_blueprint()`](https://kent-orr.github.io/spigot/reference/spigot_blueprint.md)
was called. For a blueprint defined in the app’s `R/` folder, that is
the environment Shiny loads `R/` into, so the endpoints can use any
function defined there:

``` r

# R/cars.R
fit_cars <- function(x) {
  fit <- stats::lm(stats::reformulate(x, "mpg"), data = datasets::mtcars)
  list(r_squared = summary(fit)$r.squared)
}

cars <- spigot_blueprint(
  pages = list("/" = spigot_page("list.html"), "/model" = spigot_page("model.html")),
  api = "api/cars.R"
)
```

``` r

# api/cars.R
#* @get /fit
function(x = "wt") fit_cars(x)
```

A blueprint can leave `api` out. Its pages can still call the app’s own
endpoints.

## Templates and partials

A blueprint’s `templates` are folders searched before the app’s when one
of its pages names a template file. For a page of the cars blueprint,
`spigot_page("list.html")` is found in the first of these places that
has it:

1.  The blueprint’s `templates`, in order, such as
    `templates/cars/list.html`.
2.  The app’s `templates`, in order, such as `templates/list.html`.
3.  The app’s `root`, `list.html`.

A blueprint can therefore use the app’s shared templates, or keep its
own file under a name the app also uses. Its file wins, and only for its
own pages.

Partials follow the same rule, closest first. A page’s own `partials`
win over its blueprint’s, and those win over the app’s. If the app’s
partials folder holds `nav.html` and the blueprint’s holds a `nav.html`
too, `{{> nav}}` is the blueprint’s nav on its pages and the app’s
everywhere else:

``` r

cars <- spigot_blueprint(
  pages = list("/" = spigot_page("list.html")),
  templates = "templates/cars",
  partials = "templates/cars/partials"   # its own nav.html
)

spigot_app(
  pages = list("/" = spigot_page("index.html")),
  api = "api.R",
  blueprints = list("/cars" = cars),
  templates = "templates",
  partials = "templates/partials"         # the app's nav.html, head.html, footer.html
)
```

All of these files are read, and every partial a page uses is checked,
when
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
builds the app. A missing file or partial stops the app before it serves
anything.

## Static files and `{{static}}`

A blueprint’s `static` is one folder, served at `<prefix>/static`.
httpuv sends these files directly, without running R, however the app is
launched.

Every page of a blueprint with `static` gets the folder’s URL in its
data as `{{static}}`: `cars/static` for a blueprint mounted at `/cars`,
relative to the app’s root like every other link. A template can load
its files without knowing the prefix:

``` html
<link rel="stylesheet" href="{{static}}/cars.css">
<script src="{{static}}/cars.js"></script>
```

If a page’s data has its own `static`, that one is used. A page whose
`data` is a function gets `static` added to what the function returns.

## Defining blueprints in R/

Define each blueprint in a file in the app’s `R/` folder, one file per
blueprint:

    myapp/
    ├── app.R           # spigot_app(blueprints = list("/cars" = cars, "/model" = model))
    ├── R/
    │   ├── cars.R      # cars <- spigot_blueprint(...)
    │   └── model.R     # model <- spigot_blueprint(...)
    ├── api/
    │   └── cars.R
    ├── templates/
    │   ├── cars/
    │   └── model/
    └── static/
        ├── cars/
        └── model/

Shiny loads every file in `R/`, in alphabetical order, before it runs
`app.R`, so the blueprints exist when
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
asks for them. A blueprint’s paths, like the app’s, are relative to the
app’s `root`, which is the app’s folder when the folder is run. This
only happens when the *folder* is run, with `shiny::runApp("myapp")`,
RStudio’s Run App button, Shiny Server or Posit Connect. See [Where
paths
start](https://kent-orr.github.io/spigot/articles/flask-flow.html#root).

The `site` example (`run_example("site")`) is laid out this way, with a
`cars` blueprint and a `model` blueprint.

## Blueprints are values

[`spigot_blueprint()`](https://kent-orr.github.io/spigot/reference/spigot_blueprint.md)
returns an ordinary R object, and mounting it does not change it. The
same blueprint can be mounted at more than one prefix. Its pages and
endpoints are then served under each prefix, and each mount’s pages get
their own `{{static}}`:

``` r

app <- spigot_app(
  pages = page("home"),
  api = spigot_api(),
  blueprints = list("/greet" = greet, "/hello" = greet)
)
```

Copies with different settings come from a function that returns a
blueprint. Here, two sections show different columns of the same data:

``` r

table_section <- function(title, columns) {
  spigot_blueprint(spigot_page(
    "<html><head></head><body><h1>{{title}}</h1>{{#rows}}<p>{{row}}</p>{{/rows}}</body></html>",
    data = list(
      title = title,
      rows = lapply(do.call(paste, unname(datasets::mtcars[columns])),
                    function(row) list(row = row))
    ),
    cache = TRUE
  ))
}

app <- spigot_app(
  pages = page("home"),
  api = spigot_api(),
  blueprints = list(
    "/engine" = table_section("Engine", c("cyl", "disp", "hp")),
    "/weight" = table_section("Weight", c("wt", "qsec"))
  )
)
```

Blueprints do not nest: a blueprint has pages but no `blueprints` of its
own. A section deep in a site takes a longer prefix, such as
`"/tools/greet"`.

## Compared with Flask

| Flask | spigot |
|----|----|
| `bp = Blueprint("cars", __name__, template_folder=..., static_folder=...)` | `cars <- spigot_blueprint(pages, api, templates, static = ...)` |
| `app.register_blueprint(bp, url_prefix="/cars")` | `spigot_app(blueprints = list("/cars" = cars))` |
| `@bp.route("/model")` | `"/model" = spigot_page(...)` in `pages` |
| a JSON route on the blueprint | an endpoint in its `api`, served at `/api/cars/...` |
| `url_for("cars.static", filename="cars.js")` | `{{static}}/cars.js` |
| blueprint templates searched after the app’s | blueprint templates searched *before* the app’s |

The last row is a deliberate difference. In Flask an app’s template
overrides a blueprint’s with the same name. In spigot the blueprint’s
own file wins, the way its partials do, so a section is not changed by a
file another part of the app happens to add.
