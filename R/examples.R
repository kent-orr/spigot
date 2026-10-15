#' Run a bundled example app
#'
#' Launches one of the example apps shipped in the package's `examples`
#' folder. `"minimal"` is a single hand-written HTML page that calls a plumber
#' API mounted in the same Shiny app: a GET with a query parameter, a JSON
#' POST, an endpoint that returns a data frame and validates its input, and a
#' slow async endpoint that does not block other requests.
#'
#' @param name Name of the example.
#' @param ... Passed to [shiny::runApp()], for example `port` or
#'   `launch.browser`.
#' @return The value of [shiny::runApp()], once the app is stopped.
#' @export
#' @examples
#' if (interactive()) {
#'   run_example("minimal")
#' }
run_example <- function(name = "minimal", ...) {
  shiny::runApp(example_dir(name), ...)
}

available_examples <- function() {
  root <- system.file("examples", package = "spigot")
  dirs <- list.dirs(root, full.names = FALSE, recursive = FALSE)
  sort(dirs[file.exists(file.path(root, dirs, "app.R"))])
}

example_dir <- function(name) {
  if (!is.character(name) || length(name) != 1 || is.na(name)) {
    stop("`name` must be a single example name.", call. = FALSE)
  }
  available <- available_examples()
  if (!name %in% available) {
    stop("No example called \"", name, "\". Available: ",
         paste(available, collapse = ", "), ".", call. = FALSE)
  }
  system.file("examples", name, package = "spigot")
}
