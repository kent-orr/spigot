# Run a bundled example app

Launches one of the example apps shipped in the package's `examples`
folder. Each is an app directory with an `app.R` that calls
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md);
read them with `system.file("examples", package = "spigot")`.

## Usage

``` r
run_example(name = "minimal", ...)
```

## Arguments

- name:

  Name of the example: `"minimal"`, `"live"` or `"site"`.

- ...:

  Passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html), for
  example `port` or `launch.browser`.

## Value

The value of
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html), once the
app is stopped.

## Details

- `"minimal"`: one hand-written HTML page that calls a plumber API
  mounted in the same Shiny app: a GET with a query parameter, a JSON
  POST, an endpoint that returns a data frame and validates its input,
  and a slow async endpoint that does not block other requests.

- `"live"`: a count shared by every open tab. Each click is an HTTP
  call; R pushes the new count to every tab with
  [`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md),
  and sets an input of the calling tab with
  [`spigot_trigger()`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md)
  so its server function updates a Shiny output on the page.

- `"site"`: three pages built from whisker templates that share
  partials, one rendered from data in R, and an endpoint that does its
  work in a `future` worker. Needs the future package.

## Examples

``` r
if (interactive()) {
  run_example("live")
}
# The bundled examples:
list.files(system.file("examples", package = "spigot"))
#> [1] "live"    "minimal" "site"   
```
