#' Create a Shiny app with a plumber API mounted inside it
#'
#' The API is served by the same process, origin and port as the app, under
#' `prefix`. Every other path is handled by Shiny as usual.
#'
#' @param ui The Shiny UI, as for [shiny::shinyApp()]. (Temporary: a later
#'   version replaces this with `pages`.)
#' @param server Optional Shiny server function.
#' @param api A plumber router or the path to a plumber file. A file is read
#'   with [spigot_api()]; a router is used as given, so build it from
#'   `spigot_api()` to get [spigot_json()] responses.
#' @param prefix URL path the API is mounted under.
#' @return A `shiny.appobj`.
#' @export
#' @examples
#' \dontrun{
#' api <- spigot_api() |> plumber::pr_get("/hello", function() list(msg = "hi"))
#' shiny::runApp(spigot_app(ui = shiny::fluidPage("hi"), api = api))
#' }
spigot_app <- function(ui, server = NULL, api, prefix = "/api") {
  if (missing(api)) stop("`api` is required: a plumber router or file.", call. = FALSE)
  prefix <- check_prefix(prefix)
  server <- server %||% function(input, output, session) {}
  app <- shiny::shinyApp(ui = ui, server = server)
  mount_app(app, spigot_api(api, envir = parent.frame()), prefix = prefix)
}
