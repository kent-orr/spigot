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
#' * `spigot.on(event, fn)`: calls `fn(data, event)` for each event that R
#'   pushes with [spigot_emit()] or [spigot_broadcast()]. Returns a function
#'   that removes the listener. `spigot.off(event, fn)` removes `fn`;
#'   `spigot.off(event)` removes every listener of `event`. A listener that
#'   throws does not stop the others; its error is still reported.
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
