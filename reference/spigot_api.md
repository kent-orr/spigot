# Build the API router

Returns a plumber router whose default serializer is
[`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md).

## Usage

``` r
spigot_api(file = NULL, envir = parent.frame())
```

## Arguments

- file:

  `NULL` for an empty router, the path to a plumber file, or an existing
  `Plumber` router. A router is returned unchanged; its endpoints keep
  the serializers they were created with.

- envir:

  Environment the plumber file is evaluated in.

## Value

A `Plumber` router.

## Details

plumber copies the default serializer into each endpoint when the
endpoint is created. So to get
[`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md)
for endpoints you add in code, start from `spigot_api()` and pipe them
in. Endpoints in a plumber file pick it up too. Endpoints that declare
their own serializer (for example `#* @serializer octet`) keep it.

## Examples

``` r
api <- spigot_api() |>
  plumber::pr_get("/hello", function() list(msg = "hi"))
```
