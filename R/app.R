#' Create a Shiny app with a plumber API mounted inside it
#'
#' The API is served by the same process, origin and port as the app, under
#' `prefix`. Every other path is handled by Shiny as usual.
#'
#' @section Sessions:
#' Each browser tab is a Shiny session. Its page sends the session token
#' (`Shiny.shinyapp.config.sessionId`, available once the
#' `shiny:sessioninitialized` event has fired) in an `X-Spigot-Session`
#' header, and spigot binds the request to that session; endpoints read it with
#' [spigot_session()]. A token stops working as soon as its session ends.
#'
#' With `require_session = TRUE`, API requests without a live session's token
#' get a `401` JSON response, `{"error": "session required"}`, so only open
#' pages of this app can call the API.
#'
#' API requests whose `Origin` header (or, without one, `Referer`) names
#' another host than the request's `Host` (or `X-Forwarded-Host`) get a `403`
#' JSON response, whatever `require_session` is.
#'
#' @section The browser client:
#' Every page gets `spigot.js` (see [spigot_dependency()]), which defines
#' `spigot.get()`, `spigot.post()` and friends. They send the session token
#' for you, so a page's own code calls the API with
#' `await spigot.get("items", {page: 2})`.
#'
#' @section Request size:
#' Shiny rejects request bodies larger than `getOption("shiny.maxRequestSize")`
#' (5 MB by default) before any R handler runs. That response is Shiny's own:
#' status `413` with the **plain-text** body `Maximum upload size exceeded`,
#' not JSON. Clients should not assume every error body is JSON.
#'
#' @param ui The Shiny UI, as for [shiny::shinyApp()]. (Temporary: a later
#'   version replaces this with `pages`.)
#' @param server Optional Shiny server function.
#' @param api A plumber router or the path to a plumber file. A file is read
#'   with [spigot_api()]; a router is used as given, so build it from
#'   `spigot_api()` to get [spigot_json()] responses.
#' @param prefix URL path the API is mounted under.
#' @param require_session If `TRUE`, API requests must carry the token of a
#'   live session of this app. If `FALSE`, requests without one still reach
#'   the endpoint, where [spigot_session()] returns `NULL`.
#' @param max_request_size Largest request body in bytes, applied as
#'   `options(shiny.maxRequestSize)` while the app runs (it also limits
#'   [shiny::fileInput()] uploads). `Inf` removes the limit. `NULL` leaves the
#'   option as it is.
#' @return A `shiny.appobj`.
#' @export
#' @examples
#' \dontrun{
#' api <- spigot_api() |> plumber::pr_get("/hello", function() list(msg = "hi"))
#' shiny::runApp(spigot_app(ui = shiny::fluidPage("hi"), api = api))
#' }
spigot_app <- function(ui, server = NULL, api, prefix = "/api",
                       require_session = TRUE, max_request_size = NULL) {
  if (missing(api)) stop("`api` is required: a plumber router or file.", call. = FALSE)
  prefix <- check_prefix(prefix)
  guard <- request_guard(require_session)
  check_max_request_size(max_request_size)

  ui <- attach_spigot(ui, spigot_dependency(prefix))
  app <- shiny::shinyApp(ui = ui, server = wrap_server(server))
  app <- mount_app(app, spigot_api(api, envir = parent.frame()), prefix = prefix,
                   guard = guard)
  if (!is.null(max_request_size)) {
    app <- app_on_start(app, function() {
      old <- options(shiny.maxRequestSize = max_request_size)
      shiny::onStop(function() options(old))
    })
  }
  app
}

check_max_request_size <- function(x) {
  if (is.null(x)) return(invisible())
  if (!is.numeric(x) || length(x) != 1 || is.na(x) || x <= 0) {
    stop("`max_request_size` must be a positive number of bytes, Inf, or NULL.",
         call. = FALSE)
  }
  invisible()
}
