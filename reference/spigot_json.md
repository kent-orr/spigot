# Serialise a value to JSON the spigot way

The one JSON configuration used for API responses (and, later, push
payloads). Length-1 vectors are unboxed to scalars; wrap a value in
[`I()`](https://rdrr.io/r/base/AsIs.html) to keep it as a length-1
array. `NA` and `NULL` become `null`, numbers keep full precision, data
frames become arrays of row objects, dates become `"YYYY-MM-DD"` and
date-times become ISO 8601 strings in UTC.

## Usage

``` r
spigot_json(x)
```

## Arguments

- x:

  Value to serialise.

## Value

A length-1 character vector of class `json`.

## Examples

``` r
spigot_json(list(n = 1, ids = I(7), missing = NA))
#> {"n":1,"ids":[7],"missing":null} 
spigot_json(data.frame(a = 1:2, b = c("x", "y")))
#> [{"a":1,"b":"x"},{"a":2,"b":"y"}] 
```
