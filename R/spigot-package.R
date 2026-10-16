#' @keywords internal
"_PACKAGE"

.onLoad <- function(libname, pkgname) {
  shiny::registerInputHandler("spigot.ref", resolve_trigger, force = TRUE)
}
