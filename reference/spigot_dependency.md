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

## Value

An
[`htmltools::htmlDependency()`](https://rstudio.github.io/htmltools/reference/htmlDependency.html).

## Details

The script defines `window.spigot`:

- `spigot.ready`: a promise that resolves with the session token once
  the Shiny session has started. Calls made earlier wait for it.

- `spigot.get(path, query, options)`,
  `spigot.del(path, query, options)`,
  `spigot.post(path, body, options)`, `spigot.put(path, body, options)`,
  and `spigot.request(method, path, options)` with `options` `query`,
  `body`, `headers` and `timeout` (milliseconds). They resolve with the
  parsed JSON reply (text if the reply is not JSON, `null` if it is
  empty).

- `spigot.SpigotError`: what they reject with, for a non-2xx reply or
  when no reply arrives. It has `status` (`0` for a timeout or network
  failure), `message` (the reply's JSON `error` field when there is one)
  and `body`.

- `spigot.on(event, fn)`: calls `fn(data, event)` for each event that R
  pushes with
  [`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  or
  [`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md).
  Returns a function that removes the listener. `spigot.off(event, fn)`
  removes `fn`; `spigot.off(event)` removes every listener of `event`. A
  listener that throws does not stop the others; its error is still
  reported.

On a page below the top level, which
[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
gives a `<base href>`, the script also keeps plain clicks on
`href="#section"` links on the page (see
[`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)).

Paths are relative to the API, so `spigot.get("items")` and
`spigot.get("/items")` both request `api/items` relative to the page.
This keeps working when the app is served under a subpath. Every request
carries the tab's session token in the `X-Spigot-Session` header.
`FormData`, `Blob`, `URLSearchParams` and `ArrayBuffer` bodies are sent
unchanged; any other body, strings included, is sent as JSON.

## Examples

``` r
spigot_dependency()
#> List of 10
#>  $ name      : chr "spigot"
#>  $ version   : chr "0.0.0.9000"
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
