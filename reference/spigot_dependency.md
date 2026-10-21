# The spigot.js browser client as an HTML dependency

[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
attaches this to every page, so pages normally need nothing else. Use it
directly only for a page that
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
does not serve.

## Usage

``` r
spigot_dependency(prefix = "/api")
```

## Arguments

- prefix:

  The API prefix, as given to
  [`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md).
  The script tag carries it as `data-prefix`, which is where spigot.js
  reads it from.

## Value

An
[`htmltools::htmlDependency()`](https://rstudio.github.io/htmltools/reference/htmlDependency.html).

## Details

The script defines `window.spigot`: `spigot.get()`, `spigot.post()` and
the other request functions call the API with the tab's session and
resolve with the parsed reply or reject with a `spigot.SpigotError`;
`spigot.on()` listens for events pushed with
[`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md).
See
[`vignette("client", package = "spigot")`](https://kent-orr.github.io/spigot/articles/client.md).

## Examples

``` r
spigot_dependency()
#> List of 10
#>  $ name      : chr "spigot"
#>  $ version   : chr "0.1.1"
#>  $ src       :List of 1
#>   ..$ file: chr "js"
#>  $ meta      : NULL
#>  $ script    :List of 2
#>   ..$ src        : chr "spigot.js"
#>   ..$ data-prefix: chr "/api"
#>  $ stylesheet: NULL
#>  $ head      : NULL
#>  $ attachment: NULL
#>  $ package   : chr "spigot"
#>  $ all_files : logi FALSE
#>  - attr(*, "class")= chr "html_dependency"
```
