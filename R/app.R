#' Create a Shiny app with a plumber API mounted inside it
#'
#' The API is served by the same process, origin and port as the app, under
#' `prefix`. The `pages` are served at their paths, `static` directories at
#' theirs, and every other path is handled by Shiny as usual (`www/` files,
#' for an app directory).
#'
#' @section Pages:
#' `pages` is one page, served at `/`, or a named list of them, such as
#' `list("/" = home, "/about" = about, "/docs/intro" = intro)`. A path is
#' `/` or one or more segments, not under the API `prefix`. Relative URLs in
#' every page resolve from the app's root (see [spigot_page()]).
#' `/about/` redirects to `/about`, and any other path that is not a page or
#' a file gets a `404` HTML page. Only `GET` requests reach a page.
#'
#' A page is usually a [spigot_page()]: a hand-written HTML template. A
#' top-level page (`/`, `/about`) can also be anything [shiny::shinyApp()]
#' accepts as `ui`, such as [shiny::fluidPage()], an [shiny::htmlTemplate()]
#' document, or a `function(req)` returning one of those (or an
#' [shiny::httpResponse()]). Below the top level, pages must be
#' `spigot_page()`s.
#'
#'
#' @section Sessions:
#' Each browser tab is a Shiny session. Its page sends the session token
#' (`Shiny.shinyapp.config.sessionId`, available once the
#' `shiny:sessioninitialized` event has fired) in an `X-Spigot-Session`
#' header, and spigot binds the request to that session; endpoints read it with
#' [spigot_session()]. A token stops working as soon as its session ends.
#'
#' With `require_session = TRUE`, API requests without a live session's token
#' get a `401` JSON response, `{"error": "session required", "hint": "..."}`,
#' so only open pages of this app can call the API. The `hint` points at
#' `require_session = FALSE`.
#'
#' Cross-origin API requests get a `403` JSON response, whatever
#' `require_session` is. When the browser sends `Sec-Fetch-Site`, as current
#' browsers do, only `same-origin` and `none` pass. Otherwise a request is
#' refused when its `Origin` header (or, without one, `Referer`) names
#' another host than the request's `Host` (or `X-Forwarded-Host`).
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
#' @section Blueprints:
#' `blueprints` is a list of [spigot_blueprint()]s named by prefix, such as
#' `list("/cars" = cars)`. Each blueprint's pages are served under its
#' prefix, its API under the app's `prefix` (`/api/cars/...`), and its static
#' directory at `<prefix>/static`. Its pages are checked like the app's own:
#' a path served twice, a page under the API prefix or a static path, and a
#' missing template are errors when the app is built.
#'
#' @section Files:
#' Files that pages load (scripts, stylesheets, images) can come from two
#' places. `www/` is Shiny's: its files are served at the top level
#' (`www/app.js` at `/app.js`), and only when the app directory is run (see
#' "Running the app").
#'
#' `static` is spigot's, and is served however the app is run. It is one
#' directory, served at `/static`, or a named list of directories served at
#' `/<name>` each, such as `list(js = "js", img = "assets/img")`. A relative
#' directory is relative to `root`, and a relative `root` to the working
#' directory when `spigot_app()` is called. Files are served by httpuv
#' without running R. A name must be one URL segment, other than `session`,
#' `shared` and the first segment of `prefix`, and no page may be at or
#' under a static path.
#'
#' Pages below the top level get a `<base href>` to the app's root, so
#' `<script src="static/app.js">` loads the same file from every page.
#'
#' @section Running the app:
#' Run an app directory: `shiny::runApp("myapp")` or `runApp("myapp/app.R")`,
#' as RStudio's Run App button, Shiny Server and Posit Connect do. Shiny loads
#' the files in `R/`, then sources `app.R` with the directory as the working
#' directory, serves `www/`, and keeps that working directory while the app
#' runs.
#'
#' Printing the object `spigot_app()` returns also runs the app (at the
#' console, when `app.R` is sourced with echo, or with `Rscript app.R`), but
#' Shiny then does none of that. Template and plumber file paths are relative
#' to whatever the working directory is, `www/` files get the `404` HTML page
#' (so a browser refuses to run a `www/` script), and endpoints can't call
#' functions from `R/`. `static` directories are still served. From a
#' terminal, use
#' `Rscript -e 'shiny::runApp("myapp")'`.
#'
#' @param pages One page, served at `/`, or a named list of pages keyed by
#'   path. See the Pages section.
#' @param server Optional Shiny server function.
#' @param api A plumber router or the path to a plumber file, relative to
#'   `root`. A file is read with [spigot_api()]; a router is used as given, so
#'   build it from `spigot_api()` to get [spigot_json()] responses.
#'   Blueprint APIs are mounted on it.
#' @param prefix URL path the API is mounted under.
#' @param require_session If `TRUE`, API requests must carry the token of a
#'   live session of this app. If `FALSE`, requests without one still reach
#'   the endpoint, where [spigot_session()] returns `NULL`.
#' @param max_request_size Largest request body in bytes, applied as
#'   `options(shiny.maxRequestSize)` while the app runs (it also limits
#'   [shiny::fileInput()] uploads). `Inf` removes the limit. `NULL` leaves the
#'   option as it is.
#' @param blueprints `NULL`, or a list of [spigot_blueprint()]s named by the
#'   prefix each is served under. See the Blueprints section.
#' @param templates Where [spigot_page()] template files are looked up, in
#'   order: directories, or files matched by their name. A name not found
#'   there is a path relative to `root`. `NULL` looks only there.
#' @param partials Partials every page can use: a directory, holding one
#'   partial per file named by the file name without its extension
#'   (`nav.html` is `{{> nav}}`), or a named list like [spigot_page()]'s. A
#'   page's own partials win over these.
#' @param static Directories of files to serve as they are: one directory,
#'   served at `/static`, or a named list of them, served at `/<name>` each.
#'   `NULL` serves none. See the Files section.
#' @param root The directory that relative `api`, `templates`, `partials`
#'   and `static` paths, and template file names not on the search path, are
#'   relative to, for the app and its blueprints. A relative `root` is relative to the working directory when
#'   `spigot_app()` is called.
#' @return A `shiny.appobj`.
#' @export
#' @examples
#' \dontrun{
#' api <- spigot_api() |> plumber::pr_get("/hello", function() list(msg = "hi"))
#' home <- spigot_page("<html><head></head><body><p id='msg'></p></body></html>")
#' shiny::runApp(spigot_app(pages = home, api = api))
#' }
spigot_app <- function(pages, server = NULL, api, prefix = "/api",
                       require_session = TRUE, max_request_size = NULL,
                       blueprints = NULL, templates = NULL, partials = NULL,
                       static = NULL, root = ".") {
  prefix <- check_prefix(prefix)
  pages <- as_pages(register_blueprints(as_pages(pages), blueprints, prefix))
  check_pages_vs_prefix(names(pages), prefix)
  root <- resolve_root(root)
  loader <- template_loader(templates, root)
  partials <- app_partials(partials, root, loader)
  contexts <- lapply(blueprints, blueprint_context, templates, partials, root)
  pages[] <- lapply(pages, function(page) {
    if (!inherits(page, "spigot_page")) return(page)
    ctx <- if (is.null(page$blueprint)) {
      list(loader = loader, partials = partials)
    } else {
      contexts[[page$blueprint]]
    }
    resolve_page(page, ctx$loader, ctx$partials)
  })
  static <- c(check_static(static, root, prefix), blueprint_static(blueprints, root))
  for (path in names(static)) check_pages_vs_prefix(names(pages), path, "static path")
  guard <- request_guard(require_session)
  check_max_request_size(max_request_size)

  ui <- attach_spigot(page_router(pages), spigot_dependency(prefix))
  app <- shiny::shinyApp(ui = ui, server = wrap_server(server), uiPattern = ".*")
  pr <- spigot_api(api_path(api, root), envir = parent.frame())
  pr <- mount_blueprint_apis(pr, blueprints, root)
  app <- mount_app(app, pr, prefix = prefix, guard = guard, static = static)
  if (!is.null(max_request_size)) {
    app <- app_on_start(app, function() {
      old <- options(shiny.maxRequestSize = max_request_size)
      shiny::onStop(function() options(old))
    })
  }
  app
}

# The API and static paths are answered before the pages, so a page under
# one would never be reached. `what` names the kind of path in the error, and
# `noun` what `paths` are.
check_pages_vs_prefix <- function(paths, prefix, what = "API prefix", noun = "page") {
  hidden <- paths[grepl(paste0("^", regex_escape(prefix), "(/|$)"), paths)]
  if (length(hidden)) {
    stop("The ", noun, " \"", hidden[1], "\" is under the ", what, " \"", prefix,
         "\", so it would never be served.", call. = FALSE)
  }
  invisible()
}

check_max_request_size <- function(x) {
  if (is.null(x)) return(invisible())
  if (!is.numeric(x) || length(x) != 1 || is.na(x) || x <= 0) {
    stop("`max_request_size` must be a positive number of bytes, Inf, or NULL.",
         call. = FALSE)
  }
  invisible()
}
