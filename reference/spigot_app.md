# Create a Shiny app with a plumber API mounted inside it

The API is served by the same process, origin and port as the app, under
`prefix`. The `pages` are served at their paths, `static` directories at
theirs, and every other path is handled by Shiny as usual (`www/` files,
for an app directory).

## Usage

``` r
spigot_app(
  pages,
  server = NULL,
  api,
  prefix = "/api",
  require_session = TRUE,
  max_request_size = NULL,
  blueprints = NULL,
  templates = NULL,
  partials = NULL,
  static = NULL,
  root = "."
)
```

## Arguments

- pages:

  One page, served at `/`, or a named list of pages keyed by path. See
  the Pages section.

- server:

  Optional Shiny server function.

- api:

  A plumber router or the path to a plumber file, relative to `root`. A
  file is read with
  [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md);
  a router is used as given, so build it from
  [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md)
  to get
  [`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md)
  responses. Blueprint APIs are mounted on it.

- prefix:

  URL path the API is mounted under.

- require_session:

  If `TRUE`, API requests must carry the token of a live session of this
  app. If `FALSE`, requests without one still reach the endpoint, where
  [`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md)
  returns `NULL`.

- max_request_size:

  Largest request body in bytes, applied as
  `options(shiny.maxRequestSize)` while the app runs (it also limits
  [`shiny::fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html)
  uploads). `Inf` removes the limit. `NULL` leaves the option as it is.

- blueprints:

  `NULL`, or a list of
  [`spigot_blueprint()`](https://kent-orr.github.io/spigot/reference/spigot_blueprint.md)s
  named by the prefix each is served under. See the Blueprints section.

- templates:

  Where
  [`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)
  template files are looked up, in order: directories, or files matched
  by their name. A name not found there is a path relative to `root`.
  `NULL` looks only there.

- partials:

  Partials every page can use: a directory, holding one partial per file
  named by the file name without its extension (`nav.html` is
  `{{> nav}}`), or a named list like
  [`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)'s.
  A page's own partials win over these.

- static:

  Directories of files to serve as they are: one directory, served at
  `/static`, or a named list of them, served at `/<name>` each. `NULL`
  serves none. See the Files section.

- root:

  The directory that relative `api`, `templates`, `partials` and
  `static` paths, and template file names not on the search path, are
  relative to, for the app and its blueprints. A relative `root` is
  relative to the working directory when `spigot_app()` is called.

## Value

A `shiny.appobj`.

## Pages

`pages` is one page, served at `/`, or a named list of them, such as
`list("/" = home, "/about" = about, "/docs/intro" = intro)`. A path is
`/` or one or more segments, not under the API `prefix`. Relative URLs
in every page resolve from the app's root (see
[`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)).
`/about/` redirects to `/about`, and any other path that is not a page
or a file gets a `404` HTML page. Only `GET` requests reach a page.

A page is usually a
[`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md):
a hand-written HTML template. A top-level page (`/`, `/about`) can also
be anything
[`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html)
accepts as `ui`, such as
[`shiny::fluidPage()`](https://rdrr.io/pkg/shiny/man/fluidPage.html), an
[`shiny::htmlTemplate()`](https://rdrr.io/pkg/shiny/man/reexports.html)
document, or a `function(req)` returning one of those (or an
[`shiny::httpResponse()`](https://rdrr.io/pkg/shiny/man/httpResponse.html)).
Below the top level, pages must be
[`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)s.

## Sessions

Each browser tab is a Shiny session. Its page sends the session token
(`Shiny.shinyapp.config.sessionId`, available once the
`shiny:sessioninitialized` event has fired) in an `X-Spigot-Session`
header, and spigot binds the request to that session; endpoints read it
with
[`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md).
A token stops working as soon as its session ends.

With `require_session = TRUE`, API requests without a live session's
token get a `401` JSON response,
`{"error": "session required", "hint": "..."}`, so only open pages of
this app can call the API. The `hint` points at
`require_session = FALSE`.

Cross-origin API requests get a `403` JSON response, whatever
`require_session` is. When the browser sends `Sec-Fetch-Site`, as
current browsers do, only `same-origin` and `none` pass. Otherwise a
request is refused when its `Origin` header (or, without one, `Referer`)
names another host than the request's `Host` (or `X-Forwarded-Host`).

## The browser client

Every page gets `spigot.js` (see
[`spigot_dependency()`](https://kent-orr.github.io/spigot/reference/spigot_dependency.md)),
which defines `spigot.get()`, `spigot.post()` and friends. They send the
session token for you, so a page's own code calls the API with
`await spigot.get("items", {page: 2})`.

## Request size

Shiny rejects request bodies larger than
`getOption("shiny.maxRequestSize")` (5 MB by default) before any R
handler runs. That response is Shiny's own: status `413` with the
**plain-text** body `Maximum upload size exceeded`, not JSON. Clients
should not assume every error body is JSON.

## Blueprints

`blueprints` is a list of
[`spigot_blueprint()`](https://kent-orr.github.io/spigot/reference/spigot_blueprint.md)s
named by prefix, such as `list("/cars" = cars)`. Each blueprint's pages
are served under its prefix, its API under the app's `prefix`
(`/api/cars/...`), and its static directory at `<prefix>/static`. Its
pages are checked like the app's own: a path served twice, a page under
the API prefix or a static path, and a missing template are errors when
the app is built.

## Files

Files that pages load (scripts, stylesheets, images) can come from two
places. `www/` is Shiny's: its files are served at the top level
(`www/app.js` at `/app.js`), and only when the app directory is run (see
"Running the app").

`static` is spigot's, and is served however the app is run. It is one
directory, served at `/static`, or a named list of directories served at
`/<name>` each, such as `list(js = "js", img = "assets/img")`. A
relative directory is relative to `root`, and a relative `root` to the
working directory when `spigot_app()` is called. Files are served by
httpuv without running R. A name must be one URL segment, other than
`session`, `shared` and the first segment of `prefix`, and no page may
be at or under a static path.

Pages below the top level get a `<base href>` to the app's root, so
`<script src="static/app.js">` loads the same file from every page.

## Running the app

Run an app directory: `shiny::runApp("myapp")` or
`runApp("myapp/app.R")`, as RStudio's Run App button, Shiny Server and
Posit Connect do. Shiny loads the files in `R/`, then sources `app.R`
with the directory as the working directory, serves `www/`, and keeps
that working directory while the app runs.

Printing the object `spigot_app()` returns also runs the app (at the
console, when `app.R` is sourced with echo, or with `Rscript app.R`),
but Shiny then does none of that. Template and plumber file paths are
relative to whatever the working directory is, `www/` files get the
`404` HTML page (so a browser refuses to run a `www/` script), and
endpoints can't call functions from `R/`. `static` directories are still
served. From a terminal, use `Rscript -e 'shiny::runApp("myapp")'`.

## Examples

``` r
if (FALSE) { # \dontrun{
api <- spigot_api() |> plumber::pr_get("/hello", function() list(msg = "hi"))
home <- spigot_page("<html><head></head><body><p id='msg'></p></body></html>")
shiny::runApp(spigot_app(pages = home, api = api))
} # }
```
