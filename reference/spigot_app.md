# Create a Shiny app with a plumber API mounted inside it

The API is served by the same process, origin and port as the app, under
`prefix`. The `pages` are served at their paths, and every other path is
handled by Shiny as usual (`www/` files, for an app directory).

## Usage

``` r
spigot_app(
  pages,
  server = NULL,
  api,
  prefix = "/api",
  require_session = TRUE,
  max_request_size = NULL
)
```

## Arguments

- pages:

  One page, served at `/`, or a named list of pages keyed by path. See
  the Pages section.

- server:

  Optional Shiny server function.

- api:

  A plumber router or the path to a plumber file. A file is read with
  [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md);
  a router is used as given, so build it from
  [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md)
  to get
  [`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md)
  responses.

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

API requests whose `Origin` header (or, without one, `Referer`) names
another host than the request's `Host` (or `X-Forwarded-Host`) get a
`403` JSON response, whatever `require_session` is.

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
endpoints can't call functions from `R/`. From a terminal, use
`Rscript -e 'shiny::runApp("myapp")'`.

## Examples

``` r
if (FALSE) { # \dontrun{
api <- spigot_api() |> plumber::pr_get("/hello", function() list(msg = "hi"))
home <- spigot_page("<html><head></head><body><p id='msg'></p></body></html>")
shiny::runApp(spigot_app(pages = home, api = api))
} # }
```
