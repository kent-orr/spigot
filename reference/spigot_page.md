# A page rendered from a whisker template

Describes one page of a
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md):
a complete HTML document written as a
[whisker](https://github.com/edwindj/whisker) (Mustache) template.
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
renders it when the page is requested and adds jQuery, `shiny.js` and
`spigot.js` to its `<head>`, so the template needs no
`{{ headContent() }}` and no script tags for them.

## Usage

``` r
spigot_page(template, data = list(), partials = list(), cache = FALSE)
```

## Arguments

- template:

  The template: its text, or the path of a file holding it.

- data:

  A named list of values for the template, or a function that returns
  one. A function is called for every request, with the request (the
  Rook environment) if it takes an argument.

- partials:

  A named list of partial templates: text or file names. They win over
  the app's partials of the same name.

- cache:

  If `TRUE`, the page is rendered on its first request and that result
  is served from then on. Needs static `data`.

## Value

An object of class `spigot_page`, for the `pages` argument of
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md).

## Templates

The template must be a full document with a `</head>` tag (in any case),
either in the template itself or in a partial it uses. Shiny's scripts
go just before it. A string containing `<`, `{{` or a line break is the
template text; any other string names a file holding it, read as UTF-8
when
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
builds the app. The file is looked up on the app's `templates` search
path, then relative to its `root`, which is the working directory when
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
is called (the app's directory when the app directory is run with
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html); see
"Running the app" in
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)).
File names in `partials` are looked up the same way.

The template sees only `data`, never R variables. `{{name}}` inserts a
value with HTML escaped and `{{{name}}}` inserts it as raw HTML; neither
is ever evaluated as R. Escaping covers `&`, `<`, `>` and `"` but not
`'`, so put values in double-quoted attributes (`value="{{name}}"`).
`{{> name}}` inserts the partial `name`: from `partials`, or else from
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)'s
`partials`. A partial the page uses that neither has is an error when
the app is built.

## Relative URLs

Relative URLs in every page resolve from the app's root: `href="about"`,
`href="docs/intro"` and `src="logo.png"` (a `www/` file) mean the same
on every page, and so do Shiny's own script URLs. For a page below the
top level (`/docs/intro`), spigot puts `<base href="../">` (one `../`
per level) first in its `<head>` to do this, so such a template needs a
`<head>` tag. A template with its own `<base>` keeps it.

A `<base>` would also send `href="#section"` links to the app root, so
`spigot.js` keeps plain clicks on them on the page. Other URLs relative
to the page itself, such as `href="?tab=2"`, resolve from the root too:
write the page's path (`href="docs/intro?tab=2"`).

A request for `/about/` is redirected to `/about`, where the relative
URLs resolve as intended.

## Examples

``` r
home <- spigot_page(
  "<html><head><title>{{title}}</title></head>
   <body><h1>{{title}}</h1>{{> footer}}</body></html>",
  data = list(title = "Home"),
  partials = list(footer = "<footer>spigot</footer>")
)
if (FALSE) { # \dontrun{
api <- spigot_api() |> plumber::pr_get("/hello", function() list(msg = "hi"))
shiny::runApp(spigot_app(pages = home, api = api))
} # }
```
