#' A page rendered from a whisker template
#'
#' Describes one page of a [spigot_app()]: a complete HTML document written
#' as a [whisker](https://github.com/edwindj/whisker) (Mustache) template.
#' `spigot_app()` renders it when the page is requested and adds jQuery,
#' `shiny.js` and `spigot.js` to its `<head>`, so the template needs no
#' `{{ headContent() }}` and no script tags for them.
#'
#' @section Templates:
#' The template must be a full document with a `</head>` tag (in any case),
#' either in the template itself or in a partial. Shiny's scripts go just
#' before it. A string containing `<`, `{{` or a line break is the template
#' text; any other string is the path of a file holding it, read as UTF-8
#' when `spigot_page()` is called. A relative path is relative to the working
#' directory then, which is the app's directory when the app is run with
#' [shiny::runApp()]. `partials` follow the same rule.
#'
#' The template sees only `data`, never R variables. `{{name}}` inserts a
#' value with HTML escaped and `{{{name}}}` inserts it as raw HTML; neither
#' is ever evaluated as R. Escaping covers `&`, `<`, `>` and `"` but not
#' `'`, so put values in double-quoted attributes (`value="{{name}}"`). `{{> name}}` inserts `partials$name`, and a
#' partial that is not in `partials` is an error (spigot does not look for
#' whisker's `name.mustache` files).
#'
#' @section Relative URLs:
#' Relative URLs in every page resolve from the app's root: `href="about"`,
#' `href="docs/intro"` and `src="logo.png"` (a `www/` file) mean the same
#' on every page, and so do Shiny's own script URLs. For a page below the
#' top level (`/docs/intro`), spigot puts `<base href="../">` (one `../`
#' per level) first in its `<head>` to do this, so such a template needs a
#' `<head>` tag. A template with its own `<base>` keeps it.
#'
#' A `<base>` would also send `href="#section"` links to the app root, so
#' `spigot.js` keeps plain clicks on them on the page. Other URLs relative
#' to the page itself, such as `href="?tab=2"`, resolve from the root too:
#' write the page's path (`href="docs/intro?tab=2"`).
#'
#' A request for `/about/` is redirected to `/about`, where the relative
#' URLs resolve as intended.
#'
#' @param template The template: its text, or the path of a file holding it.
#' @param data A named list of values for the template, or a function that
#'   returns one. A function is called for every request, with the request
#'   (the Rook environment) if it takes an argument.
#' @param partials A named list of partial templates: text or file paths.
#' @param cache If `TRUE`, the page is rendered on its first request and that
#'   result is served from then on. Needs static `data`.
#' @return An object of class `spigot_page`, for the `pages` argument of
#'   [spigot_app()].
#' @export
#' @examples
#' home <- spigot_page(
#'   "<html><head><title>{{title}}</title></head>
#'    <body><h1>{{title}}</h1>{{> footer}}</body></html>",
#'   data = list(title = "Home"),
#'   partials = list(footer = "<footer>spigot</footer>")
#' )
#' \dontrun{
#' api <- spigot_api() |> plumber::pr_get("/hello", function() list(msg = "hi"))
#' shiny::runApp(spigot_app(pages = home, api = api))
#' }
spigot_page <- function(template, data = list(), partials = list(), cache = FALSE) {
  if (!is_string(template)) {
    stop("`template` must be a single string: template text or a file path.", call. = FALSE)
  }
  label <- template_label(template)
  template <- read_template(template, "template")
  partials <- check_partials(partials)
  check_data(data)
  if (!is_flag(cache)) stop("`cache` must be TRUE or FALSE.", call. = FALSE)
  if (cache && is.function(data)) {
    stop("`cache = TRUE` needs a list for `data`: cache requires static data.", call. = FALSE)
  }
  if (!any(has_head_end(c(template, unlist(partials))))) {
    stop("The template ", label, " has no </head>; spigot needs a full HTML ",
         "document to add Shiny's scripts to.", call. = FALSE)
  }
  check_partial_refs(c(list(template = template), partials), names(partials))

  render_html <- function(req) {
    values <- if (is.function(data)) call_with_req(data, req) else data
    if (!is.list(values)) {
      stop("The `data` function of the page ", label, " must return a list.", call. = FALSE)
    }
    render_whisker(template, values, partials)
  }
  # `base`: the <base href> for a page served below the top level, or NULL.
  # The cache holds the HTML before it, as one page may be served at several
  # depths.
  cached <- NULL
  render <- function(req, base = NULL) {
    html <- if (!cache) render_html(req) else cached %||% (cached <<- render_html(req))
    as_html_document(html, label, base)
  }

  structure(list(label = label, data = data, partials = names(partials), cache = cache,
                 render = render),
            class = "spigot_page")
}

#' @export
print.spigot_page <- function(x, ...) {
  cat("<spigot_page> ", x$label, "\n", sep = "")
  cat("  data:     ", if (is.function(x$data)) "function, per request" else "static", "\n",
      sep = "")
  if (length(x$partials)) cat("  partials: ", paste(x$partials, collapse = ", "), "\n", sep = "")
  cat("  cache:    ", if (x$cache) "yes" else "no", "\n", sep = "")
  invisible(x)
}

# ---- templates ---------------------------------------------------------------------

is_string <- function(x) is.character(x) && length(x) == 1 && !is.na(x)

looks_like_text <- function(x) grepl("<|\\{\\{|\n", x)

template_label <- function(x) {
  if (!looks_like_text(x)) return(sprintf("\"%s\"", x))
  x <- gsub("\\s+", " ", x)
  sprintf("\"%s\"", if (nchar(x) > 40) paste0(substr(x, 1, 37), "...") else x)
}

# Template text as given, or the contents of the file it names.
read_template <- function(x, what) {
  if (looks_like_text(x)) return(enc2utf8(x))
  if (!file.exists(x) || dir.exists(x)) {
    stop("Can't find the ", what, " file \"", x, "\" (relative to ", getwd(), "). ",
         "Template text must contain '<', '{{' or a line break.", call. = FALSE)
  }
  lines <- readLines(x, encoding = "UTF-8", warn = FALSE)
  enc2utf8(paste(lines, collapse = "\n"))
}

check_partials <- function(partials) {
  ok <- is.list(partials) && (!length(partials) ||
    (!is.null(names(partials)) && all(nzchar(names(partials))) && !anyDuplicated(names(partials))))
  if (!ok) stop("`partials` must be a list with a unique name for each partial.", call. = FALSE)
  for (nm in names(partials)) {
    if (!is_string(partials[[nm]])) {
      stop("`partials$", nm, "` must be a single string: template text or a file path.",
           call. = FALSE)
    }
    partials[[nm]] <- read_template(partials[[nm]], paste0("partial \"", nm, "\""))
  }
  partials
}

check_data <- function(data) {
  if (is.function(data)) return(invisible())
  named <- !length(data) || (!is.null(names(data)) && all(nzchar(names(data))))
  if (!is.list(data) || !named) {
    stop("`data` must be a named list, or a function returning one.", call. = FALSE)
  }
  invisible()
}

has_head_end <- function(x) grepl("</head\\s*>", x, ignore.case = TRUE)

# Partials named in `{{> name}}` tags must be supplied. (A tag after a
# delimiter change is not seen here; render_whisker() catches it.)
check_partial_refs <- function(texts, available) {
  for (where in names(texts)) {
    m <- regmatches(texts[[where]], gregexpr("\\{\\{\\s*>\\s*([^}[:space:]]+)\\s*\\}\\}",
                                             texts[[where]]))[[1]]
    used <- unique(gsub("^\\{\\{\\s*>\\s*|\\s*\\}\\}$", "", m))
    missing <- setdiff(used, available)
    if (length(missing)) {
      stop("The ", if (where == "template") "template" else paste0("partial \"", where, "\""),
           " uses the partial \"", missing[1], "\", which is not in `partials`.", call. = FALSE)
    }
  }
  invisible()
}

# The one place whisker runs. whisker falls back to reading "<name>.mustache"
# from the working directory for a partial it was not given; render from an
# empty directory and make that case an error instead.
render_whisker <- function(template, data, partials) {
  in_dir(empty_dir(), withCallingHandlers(
    whisker::whisker.render(template, data = data, partials = partials),
    warning = function(w) {
      msg <- conditionMessage(w)
      if (startsWith(msg, "No partial")) {
        stop("spigot_page(): ", sub(" or file .*$", "", msg), " in `partials`.", call. = FALSE)
      }
    }
  ))
}

empty_dir <- function() {
  dir <- file.path(tempdir(), "spigot-empty")
  if (!dir.exists(dir)) dir.create(dir)
  dir
}

in_dir <- function(dir, code) {
  old <- setwd(dir)
  on.exit(setwd(old))
  force(code)
}

# Split rendered HTML at its first </head> and hand both halves to Shiny as
# HTML() values in a fixed template, so Shiny adds its <head> content there
# and nothing the page rendered is ever read as an htmlTemplate (DECISIONS.md,
# M0 step 4). A `base` href goes first in <head>, unless the page has a <base>.
as_html_document <- function(html, label, base = NULL) {
  at <- regexpr("</head\\s*>", html, ignore.case = TRUE)
  if (at < 0) {
    stop("The page ", label, " rendered without a </head>; spigot needs a full HTML ",
         "document to add Shiny's scripts to.", call. = FALSE)
  }
  head <- substr(html, 1L, at - 1L)
  rest <- substr(html, at + attr(at, "match.length"), nchar(html))
  if (!is.null(base)) head <- insert_base(head, base, label)
  htmltools::htmlTemplate(
    text_ = "{{ head }}{{ headContent() }}</head>{{ rest }}",
    head = htmltools::HTML(head), rest = htmltools::HTML(rest), document_ = TRUE
  )
}

insert_base <- function(head, base, label) {
  if (grepl("<base[\\s>]", head, ignore.case = TRUE, perl = TRUE)) return(head)
  open <- regexpr("<head(\\s[^>]*)?>", head, ignore.case = TRUE, perl = TRUE)
  if (open < 0) {
    stop("The page ", label, " is served below the top level, so it needs a <head> tag ",
         "for spigot to put a <base href> in.", call. = FALSE)
  }
  end <- open + attr(open, "match.length") - 1L
  paste0(substr(head, 1L, end), "<base href=\"", base, "\" data-spigot>",
         substr(head, end + 1L, nchar(head)))
}

# ---- routing -------------------------------------------------------------------------

PAGE_PATH <- "^/([A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*)?$"

is_page_path <- function(path) {
  grepl(PAGE_PATH, path) & !grepl("(^|/)\\.+(/|$)", path) &
    !strsplit_first(path) %in% reserved_prefixes
}

strsplit_first <- function(path) vapply(strsplit(path, "/", fixed = TRUE),
                                         function(x) x[2] %||% "", character(1))

# "../" once per level below the top: the <base href> that points a page at
# the app root, or NULL for a top-level page.
base_href <- function(path) {
  depth <- lengths(regmatches(path, gregexpr("/", path, fixed = TRUE))) - 1L
  if (depth > 0) strrep("../", depth)
}

# `pages` as spigot_app() takes it: one page (served at "/") or a named list
# of them. A page is a spigot_page or anything shiny::shinyApp() takes as ui.
as_pages <- function(pages) {
  if (is.list(pages) && !is.object(pages)) {
    if (!length(pages)) stop("`pages` must have at least one page.", call. = FALSE)
    if (is.null(names(pages))) {
      stop("`pages` must be named by path, as in list(\"/\" = home, \"/about\" = about).",
           call. = FALSE)
    }
  } else {
    pages <- list("/" = pages)
  }
  paths <- names(pages)
  bad <- !is_page_path(paths)
  if (any(bad)) {
    stop("Page path \"", paths[bad][1], "\" is not allowed. A path is \"/\" or segments ",
         "such as \"/about\" or \"/docs/intro\": a leading slash, no trailing slash, only ",
         "letters, digits, '.', '_', '~' or '-' in each segment, no \".\" or \"..\", and ",
         "not under /session or /shared.", call. = FALSE)
  }
  if (anyDuplicated(paths)) {
    stop("Page path \"", paths[duplicated(paths)][1], "\" appears more than once.", call. = FALSE)
  }
  for (p in paths) {
    if (is.null(pages[[p]])) stop("The page at \"", p, "\" is NULL.", call. = FALSE)
    if (!is.null(base_href(p)) && !inherits(pages[[p]], "spigot_page")) {
      stop("The page at \"", p, "\" must be a spigot_page(): Shiny UI below the top level ",
           "would load Shiny's scripts from the wrong place.", call. = FALSE)
    }
  }
  pages
}

# A ui function for shiny::shinyApp(uiPattern = ".*"). Returns the page's UI,
# a redirect, a 404, or NULL for paths Shiny serves after the ui handler.
page_router <- function(pages) {
  force(pages)
  function(req) {
    path <- req$PATH_INFO %||% "/"
    page <- pages[[path]]
    if (!is.null(page)) return(render_page(page, req, base_href(path)))
    if (path == "/reactlog" || startsWith(path, "/reactlog/")) return(NULL)
    trimmed <- sub("/$", "", path)
    if (trimmed != path && trimmed != "/" && !is.null(pages[[trimmed]])) {
      # Relative, so it stays right under a proxy subpath.
      target <- paste0("../", basename(trimmed), req$QUERY_STRING %||% "")
      return(shiny::httpResponse(301L, content_type = "text/plain; charset=UTF-8",
                                 content = "Moved", headers = list(Location = target)))
    }
    not_found()
  }
}

render_page <- function(page, req, base = NULL) {
  if (inherits(page, "spigot_page")) return(page$render(req, base))
  if (is.function(page)) call_with_req(page, req) else page
}

not_found <- function() {
  shiny::httpResponse(
    404L, content_type = "text/html; charset=UTF-8",
    content = paste0("<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">",
                     "<title>Not found</title></head><body><h1>Not found</h1>",
                     "<p>There is no page at this address.</p></body></html>")
  )
}
