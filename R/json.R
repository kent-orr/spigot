#' Serialise a value to JSON the spigot way
#'
#' The one JSON configuration used for API responses (and, later, push
#' payloads). Length-1 vectors are unboxed to scalars; wrap a value in [I()]
#' to keep it as a length-1 array. `NA` and `NULL` become `null`, numbers keep
#' full precision, data frames become arrays of row objects, dates become
#' `"YYYY-MM-DD"` and date-times become ISO 8601 strings in UTC.
#'
#' @param x Value to serialise.
#' @return A length-1 character vector of class `json`.
#' @export
#' @examples
#' spigot_json(list(n = 1, ids = I(7), missing = NA))
#' spigot_json(data.frame(a = 1:2, b = c("x", "y")))
spigot_json <- function(x) {
  jsonlite::toJSON(
    x,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    dataframe = "rows",
    POSIXt = "ISO8601",
    UTC = TRUE
  )
}
