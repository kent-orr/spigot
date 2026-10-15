#' The spigot.js browser client as an HTML dependency
#'
#' [spigot_app()] attaches this to every page, so pages normally need nothing
#' else. Use it directly only for a page that `spigot_app()` does not serve.
#'
#' The script defines `window.spigot`:
#'
#' * `spigot.ready`: a promise that resolves with the session token once the
#'   Shiny session has started. Calls made earlier wait for it.
#' * `spigot.get(path, query, options)`, `spigot.del(path, query, options)`,
#'   `spigot.post(path, body, options)`, `spigot.put(path, body, options)`, and
#'   `spigot.request(method, path, options)` with `options` `query`, `body`,
#'   `headers` and `timeout` (milliseconds). They resolve with the parsed JSON
#'   reply (text if the reply is not JSON, `null` if it is empty).
#' * `spigot.SpigotError`: what they reject with, for a non-2xx reply or when
#'   no reply arrives. It has `status` (`0` for a timeout or network failure),
#'   `message` (the reply's JSON `error` field when there is one) and `body`.
#'
#' Paths are relative to the API, so `spigot.get("items")` and
#' `spigot.get("/items")` both request `api/items` relative to the page. This
#' keeps working when the app is served under a subpath. Every request carries
#' the tab's session token in the `X-Spigot-Session` header. `FormData`,
#' `Blob`, `URLSearchParams` and `ArrayBuffer` bodies are sent unchanged; any
#' other body, strings included, is sent as JSON.
#'
#' @param prefix The API prefix, as given to [spigot_app()].
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
# request. An httpResponse from a ui function passes through untouched.
attach_spigot <- function(ui, dep) {
  force(ui)
  force(dep)
  function(req) {
    x <- if (!is.function(ui)) ui else if (length(formals(ui))) ui(req) else ui()
    if (inherits(x, "httpResponse")) return(x)
    htmltools::attachDependencies(x, dep, append = TRUE)
  }
}
