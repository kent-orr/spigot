#' A blueprint: pages, an API and files that belong together
#'
#' A blueprint groups the pages of one part of an app with the API endpoints,
#' templates, partials and static files they use. [spigot_app()] mounts it
#' under a prefix: `spigot_app(blueprints = list("/cars" = cars))` serves its
#' page `/` at `/cars` and its page `/model` at `/cars/model`. Define
#' blueprints in the app's `R/` directory, which Shiny loads before `app.R`.
#'
#' Its API is mounted under the app's API prefix: with the default `prefix`,
#' the blueprint's `/fit` endpoint is `/api/cars/fit`, which a page calls with
#' `spigot.get("cars/fit")`. The app's session and origin checks apply to it.
#'
#' Its template files are looked up in `templates` first, then on the app's
#' search path. Its `partials` win over the app's, and a page's own over
#' both. Its `static` directory is served at `<prefix>/static`, and every
#' blueprint page gets that path, relative to the app root, as `{{static}}` in
#' its data (`"cars/static"`), so `<script src="{{static}}/cars.js">` works
#' on any of its pages. A `static` key in a page's own data wins.
#'
#' Paths are relative to the app's `root` and are read when `spigot_app()`
#' builds the app, as template files are.
#'
#' @param pages One page, served at the prefix, or a named list of pages keyed
#'   by path below it, such as `list("/" = list_page, "/model" = model_page)`.
#' @param api `NULL`, the path of a plumber file, or a plumber router. A file
#'   is read with [spigot_api()] in the environment `spigot_blueprint()` is
#'   called from.
#' @param templates Directories or files searched for the blueprint's template
#'   files, before the app's. See `templates` in [spigot_app()].
#' @param partials A directory or a named list of partials, as in
#'   [spigot_app()].
#' @param static A directory, served at `<prefix>/static`.
#' @return An object of class `spigot_blueprint`, for the `blueprints`
#'   argument of [spigot_app()].
#' @export
#' @examples
#' cars <- spigot_blueprint(
#'   pages = list("/" = spigot_page("list.html"), "/model" = spigot_page("model.html")),
#'   api = "api/cars.R",
#'   templates = "templates/cars",
#'   static = "static/cars"
#' )
#' cars
spigot_blueprint <- function(pages, api = NULL, templates = NULL, partials = NULL,
                             static = NULL) {
  pages <- as_pages(pages)
  if (!is.null(api) && !is_string(api) && !inherits(api, "Plumber")) {
    stop("`api` must be NULL, the path of a plumber file, or a plumber router.", call. = FALSE)
  }
  if (!is.null(templates) && (!is.character(templates) || anyNA(templates))) {
    stop("`templates` must be NULL or directory and file paths.", call. = FALSE)
  }
  if (!is.null(partials) && !is_string(partials) && !is.list(partials)) {
    stop("`partials` must be NULL, a directory, or a named list of partials.", call. = FALSE)
  }
  if (!is.null(static) && !is_string(static)) {
    stop("`static` must be NULL or one directory.", call. = FALSE)
  }
  structure(list(pages = pages, api = api, templates = templates, partials = partials,
                 static = static, envir = parent.frame()),
            class = "spigot_blueprint")
}

#' @export
print.spigot_blueprint <- function(x, ...) {
  api <- if (is.null(x$api)) "none" else if (is.character(x$api)) x$api else "router"
  cat("<spigot_blueprint>\n")
  cat("  pages:     ", paste(names(x$pages), collapse = ", "), "\n", sep = "")
  cat("  api:       ", api, "\n", sep = "")
  if (length(x$templates)) cat("  templates: ", paste(x$templates, collapse = ", "), "\n", sep = "")
  if (is.character(x$partials)) cat("  partials:  ", x$partials, "\n", sep = "")
  if (length(x$static)) cat("  static:    ", x$static, "\n", sep = "")
  invisible(x)
}

# `app_pages` (from as_pages()) with every blueprint's pages added under its
# prefix. A blueprint's spigot_page()s record their blueprint, for
# resolve_page(), and get `static` in their data when it has static files.
register_blueprints <- function(app_pages, blueprints, prefix) {
  if (is.null(blueprints)) return(app_pages)
  check_blueprints(blueprints, prefix)
  owner <- stats::setNames(rep("the app", length(app_pages)), names(app_pages))
  for (bp_prefix in names(blueprints)) {
    bp <- blueprints[[bp_prefix]]
    for (path in names(bp$pages)) {
      full <- if (path == "/") bp_prefix else paste0(bp_prefix, path)
      if (!is.na(owner[full])) {
        stop("The page \"", full, "\" of the blueprint \"", bp_prefix, "\" is also a page of ",
             owner[[full]], ".", call. = FALSE)
      }
      page <- bp$pages[[path]]
      if (inherits(page, "spigot_page")) {
        page$blueprint <- bp_prefix
        if (!is.null(bp$static)) page$data <- with_static(page$data, static_url(bp_prefix))
      }
      app_pages[[full]] <- page
      owner[[full]] <- paste0("the blueprint \"", bp_prefix, "\"")
    }
  }
  app_pages
}

check_blueprints <- function(blueprints, prefix) {
  if (!is.list(blueprints) || is.null(names(blueprints)) || any(names(blueprints) == "")) {
    stop("`blueprints` must be a list named by prefix, as in list(\"/cars\" = cars).",
         call. = FALSE)
  }
  prefixes <- names(blueprints)
  bad <- prefixes[!is_page_path(prefixes) | prefixes == "/"]
  if (length(bad)) {
    stop("The blueprint prefix \"", bad[1], "\" is not allowed. A prefix is a page path ",
         "other than \"/\", such as \"/cars\".", call. = FALSE)
  }
  if (anyDuplicated(prefixes)) {
    stop("The blueprint prefix \"", prefixes[duplicated(prefixes)][1],
         "\" appears more than once.", call. = FALSE)
  }
  for (p in prefixes) {
    if (!inherits(blueprints[[p]], "spigot_blueprint")) {
      stop("The blueprint at \"", p, "\" must be a spigot_blueprint().", call. = FALSE)
    }
  }
  check_pages_vs_prefix(prefixes, prefix, noun = "blueprint")
  invisible()
}

# The URL path of a blueprint's static files, relative to the app root, as
# templates see it in `{{static}}`.
static_url <- function(bp_prefix) paste0(sub("^/", "", bp_prefix), "/static")

# `data` with `static` added, unless it has its own.
with_static <- function(data, url) {
  add <- function(values) {
    if (!is.list(values) || "static" %in% names(values)) return(values)
    c(values, list(static = url))
  }
  if (is.function(data)) function(req) add(call_with_req(data, req)) else add(data)
}

# How a blueprint's pages resolve: its search path in front of the app's, its
# partials over the app's.
blueprint_context <- function(bp, templates, partials, root) {
  loader <- template_loader(c(bp$templates, templates), root)
  list(loader = loader,
       partials = merge_partials(partials, app_partials(bp$partials, root, loader)))
}

# The blueprints' static dirs, keyed by URL path, for mount_app().
blueprint_static <- function(blueprints, root) {
  out <- list()
  for (bp_prefix in names(blueprints)) {
    static <- blueprints[[bp_prefix]]$static
    if (!is.null(static)) {
      out[[paste0(bp_prefix, "/static")]] <- check_static(static, root)[[1]]
    }
  }
  out
}

# Mount each blueprint's API on `pr` at its prefix.
mount_blueprint_apis <- function(pr, blueprints, root) {
  for (bp_prefix in names(blueprints)) {
    bp <- blueprints[[bp_prefix]]
    if (is.null(bp$api)) next
    plumber::pr_mount(pr, bp_prefix, spigot_api(api_path(bp$api, root), envir = bp$envir))
  }
  pr
}

# A plumber file path relative to `root`; anything else as it is.
api_path <- function(api, root) {
  if (is_string(api) && !is_absolute(api)) file.path(root, api) else api
}
