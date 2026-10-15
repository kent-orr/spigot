#' Build the API router
#'
#' Returns a plumber router whose default serializer is [spigot_json()].
#'
#' plumber copies the default serializer into each endpoint when the endpoint
#' is created. So to get [spigot_json()] for endpoints you add in code, start
#' from `spigot_api()` and pipe them in. Endpoints in a plumber file pick it up
#' too. Endpoints that declare their own serializer (for example
#' `#* @serializer octet`) keep it.
#'
#' @param file `NULL` for an empty router, the path to a plumber file, or an
#'   existing `Plumber` router. A router is returned unchanged; its endpoints
#'   keep the serializers they were created with.
#' @param envir Environment the plumber file is evaluated in.
#' @return A `Plumber` router.
#' @export
#' @examples
#' api <- spigot_api() |>
#'   plumber::pr_get("/hello", function() list(msg = "hi"))
spigot_api <- function(file = NULL, envir = parent.frame()) {
  if (inherits(file, "Plumber")) return(file)
  pr <- if (is.null(file)) {
    plumber::pr(envir = envir)
  } else if (is.character(file) && length(file) == 1 && !is.na(file)) {
    if (!file.exists(file)) stop("plumber file not found: ", file, call. = FALSE)
    plumber::pr(file, envir = envir)
  } else {
    stop("`file` must be NULL, a path to a plumber file, or a plumber router.",
         call. = FALSE)
  }
  pr$setSerializer(spigot_serializer())
  pr
}

spigot_serializer <- function() {
  plumber::serializer_content_type("application/json", function(val) spigot_json(val))
}
