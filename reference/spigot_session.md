# The Shiny session bound to an API request

Call this inside a plumber endpoint to get the session of the browser
tab that made the request. The tab's page sends its session token in the
`X-Spigot-Session` header, and spigot binds the request to the session
before the endpoint runs. Use the session to read per-tab state
(`session$userData`, or reactive values with
[`shiny::isolate()`](https://rdrr.io/pkg/shiny/man/isolate.html)).

## Usage

``` r
spigot_session(req)
```

## Arguments

- req:

  The `req` argument of a plumber endpoint.

## Value

The `ShinySession`, or `NULL` when the request is not bound to one.

## Details

With `spigot_app(require_session = TRUE)` (the default), requests
without a live session never reach the endpoint, so the result is never
`NULL`.

## Examples

``` r
if (FALSE) { # \dontrun{
#* @get /visits
function(req) {
  s <- spigot::spigot_session(req)
  s$userData$visits <- sum(s$userData$visits, 1)
  list(visits = s$userData$visits)
}
} # }
```
