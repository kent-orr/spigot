# The only file that knows the shape of a shiny.appobj (PLAN 4.1, F1).

# Path segments Shiny serves itself. A prefix here would hide them.
reserved_prefixes <- c("session", "shared")

check_prefix <- function(prefix) {
  ok <- is.character(prefix) && length(prefix) == 1 && !is.na(prefix) &&
    grepl("^(/[A-Za-z0-9._~-]+)+$", prefix)
  if (!ok) {
    stop("`prefix` must look like \"/api\": a leading slash, no trailing slash, ",
         "and only letters, digits, '.', '_', '~' or '-' in each segment.", call. = FALSE)
  }
  first <- strsplit(prefix, "/", fixed = TRUE)[[1]][2]
  if (first %in% reserved_prefixes) {
    stop("`prefix` must not start with /", first, ": Shiny serves that path itself.",
         call. = FALSE)
  }
  prefix
}

# Returns function(req). Requests under `prefix` go to `pr$call(req)` with the
# prefix moved from PATH_INFO to SCRIPT_NAME; everything else goes to
# `fallback(req)`. `guard(req)` may return an httpResponse to short-circuit.
# The result is an httpResponse, or a promise of one.
spigot_mount_handler <- function(pr, prefix = "/api", fallback = function(req) NULL,
                                 guard = NULL) {
  force(pr)
  force(fallback)
  prefix <- check_prefix(prefix)
  pattern <- paste0("^", regex_escape(prefix), "(/|$)")

  function(req) {
    path <- req$PATH_INFO
    if (is.null(path) || !grepl(pattern, path)) return(fallback(req))

    old_script <- req$SCRIPT_NAME %||% ""
    restore <- function() {
      req$SCRIPT_NAME <- old_script
      req$PATH_INFO <- path
    }
    # plumber routes after async filters resolve, so the rewritten path must
    # live until the promise settles, not just until this function returns.
    async <- FALSE
    on.exit(if (!async) restore())

    req$SCRIPT_NAME <- paste0(old_script, prefix)
    rest <- substring(path, nchar(prefix) + 1L)
    req$PATH_INFO <- if (identical(rest, "")) "/" else rest

    tryCatch({
      if (!is.null(guard)) {
        denied <- guard(req)
        if (!is.null(denied)) return(denied)
      }
      res <- pr$call(req)
      if (!promises::is.promising(res)) return(rook_to_httpResponse(res))
      async <- TRUE
      res |>
        promises::then(rook_to_httpResponse) |>
        promises::catch(mount_failure) |>
        promises::finally(restore)
    }, error = mount_failure)
  }
}

mount_failure <- function(e) {
  message("spigot: API request failed: ", conditionMessage(e))
  json_error(500L, "internal server error")
}

# Put the API in front of the app's own HTTP handler, and keep httpuv's static
# file serving away from the prefix.
mount_app <- function(app, pr, prefix = "/api", guard = NULL) {
  if (!inherits(app, "shiny.appobj")) {
    stop("`app` must be a shiny.appobj (from shiny::shinyApp()).", call. = FALSE)
  }
  if (!is.function(app$httpHandler)) {
    stop("This shiny.appobj has no httpHandler function; the installed shiny ",
         "version may have changed its structure. spigot needs shiny >= 1.14.0.",
         call. = FALSE)
  }
  # spigot_mount_handler() forces `fallback`, so this captures the original
  # handler before the field is replaced (otherwise it would call itself).
  app$httpHandler <- spigot_mount_handler(pr, prefix, fallback = app$httpHandler,
                                          guard = guard)

  # An app directory with www/ makes httpuv serve "/" as a static path. httpuv
  # answers non-GET requests under it with 400 itself, before R sees them. The
  # httpuv server only exists after onStart, so exclude the prefix on the first
  # event-loop tick, which runs before any request is handled in R.
  app_on_start(app, function() {
    later::later(function() {
      exclude_static_prefix(shiny::getShinyOption("server", default = NULL), prefix)
    })
  })
}

# Run `fn` when the app starts, after the app's own onStart.
app_on_start <- function(app, fn) {
  force(fn)
  user_on_start <- app$onStart
  app$onStart <- function() {
    if (is.function(user_on_start)) user_on_start()
    fn()
  }
  app
}

# `server` is the running httpuv WebServer (the object shiny::addResourcePath()
# also updates), or NULL when the app is not run by shiny::runApp().
exclude_static_prefix <- function(server, prefix) {
  if (is.null(server)) return(FALSE)
  server$setStaticPath(.list = stats::setNames(list(httpuv::excludeStaticPath()), prefix))
  TRUE
}

# ---- request guards (PLAN 4.2) -------------------------------------------------
# A guard is function(req) returning NULL to let the request through, or an
# httpResponse to answer it without calling the router. Guards run after the
# prefix is stripped and only for API requests.

SPIGOT_HEADER <- "HTTP_X_SPIGOT_SESSION"

# The guard spigot_app() installs: origin first, then session.
request_guard <- function(require_session = TRUE) {
  if (!is_flag(require_session)) {
    stop("`require_session` must be TRUE or FALSE.", call. = FALSE)
  }
  guards <- list(origin_guard(), session_guard(require_session))
  function(req) {
    for (g in guards) {
      denied <- g(req)
      if (!is.null(denied)) return(denied)
    }
    NULL
  }
}

# Binds the request to the live session named by its X-Spigot-Session header
# (req$spigot_session, read by spigot_session()). With require_session, a
# request without one gets 401. Malformed tokens never reach the registry.
session_guard <- function(require_session = TRUE) {
  force(require_session)
  function(req) {
    token <- req[[SPIGOT_HEADER]]
    session <- if (is_token(token)) lookup_session(token)
    if (is.null(session)) {
      if (require_session) return(json_error(401L, "session required"))
      return(NULL)
    }
    req$spigot_session <- session
    NULL
  }
}

# Refuses requests whose Origin (or, without one, Referer) names another host
# than the one the request was sent to. Browsers send Origin on same-origin
# POST/PUT/DELETE and nothing on same-origin GET, so absent means allowed.
# Behind a proxy that rewrites Host, X-Forwarded-Host also counts.
origin_guard <- function() {
  function(req) {
    source <- req$HTTP_ORIGIN %||% req$HTTP_REFERER
    if (is.null(source)) return(NULL)
    if (same_origin(source, req)) NULL else json_error(403L, "cross-origin request refused")
  }
}

same_origin <- function(source, req) {
  m <- regmatches(source, regexec("^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#@]*)([/?#]|$)", source))[[1]]
  if (!length(m)) return(FALSE) # "null", relative, userinfo, or not a URL
  scheme <- tolower(m[2])
  origin <- strip_default_port(tolower(m[3]), scheme)
  hosts <- c(req$HTTP_HOST, strsplit(req$HTTP_X_FORWARDED_HOST %||% "", ",", fixed = TRUE)[[1]])
  hosts <- strip_default_port(tolower(trimws(hosts)), scheme)
  nzchar(origin) && origin %in% hosts[nzchar(hosts)]
}

strip_default_port <- function(authority, scheme) {
  port <- switch(scheme, http = ":80", https = ":443", NULL)
  if (is.null(port)) return(authority)
  sub(paste0(port, "$"), "", authority)
}
