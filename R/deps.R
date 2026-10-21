#' The spigot.js browser client as an HTML dependency
#'
#' [spigot_app()] attaches this to every page, so pages normally need nothing
#' else. Use it directly only for a page that `spigot_app()` does not serve.
#'
#' The script defines `window.spigot`: `spigot.get()`, `spigot.post()` and
#' the other request functions call the API with the tab's session and
#' resolve with the parsed reply or reject with a `spigot.SpigotError`;
#' `spigot.on()` listens for events pushed with [spigot_emit()]. See
#' `vignette("client", package = "spigot")`.
#'
#' @param prefix The API prefix, as given to [spigot_app()]. The script tag
#'   carries it as `data-prefix`, which is where spigot.js reads it from.
#' @return An [htmltools::htmlDependency()].
#' @export
#' @examples
#' spigot_dependency()
spigot_dependency <- function(prefix = "/api") {
  prefix <- check_prefix(prefix)
  htmltools::htmlDependency(
    "spigot", as.character(utils::packageVersion("spigot")),
    src = c(file = "js"), package = "spigot",
    script = list(src = "spigot.js", `data-prefix` = prefix),
    all_files = FALSE
  )
}

# Make `ui` (anything shiny::shinyApp() accepts) carry `dep` on every
# request. An httpResponse or NULL from a ui function passes through
# untouched (NULL makes Shiny try its next handler).
attach_spigot <- function(ui, dep) {
  force(ui)
  force(dep)
  function(req) {
    x <- if (is.function(ui)) call_with_req(ui, req) else ui
    if (is.null(x) || inherits(x, "httpResponse")) return(x)
    htmltools::attachDependencies(x, dep, append = TRUE)
  }
}
