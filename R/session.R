# Session registry: Shiny session token -> live ShinySession (PLAN 4.2).
#
# Every session of a spigot app registers here when its server function
# starts and is removed when it ends. The API guard looks the token from the
# X-Spigot-Session header up here to bind a request to its tab.

.registry <- new.env(parent = emptyenv())

# Shiny tokens are createUniqueId(16): 32 lowercase hex characters (F7).
is_token <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && grepl("^[0-9a-f]{16,}$", x)
}

register_session <- function(session) {
  token <- session$token
  if (!is_token(token)) {
    stop("Cannot register a session without a valid token.", call. = FALSE)
  }
  if (identical(get0(token, envir = .registry, inherits = FALSE), session)) {
    return(invisible(session))
  }
  assign(token, session, envir = .registry)
  session$onSessionEnded(function() unregister_session(token, session))
  invisible(session)
}

unregister_session <- function(token, session) {
  if (identical(get0(token, envir = .registry, inherits = FALSE), session)) {
    rm(list = token, envir = .registry)
  }
  invisible()
}

# The live session for `token`, or NULL.
lookup_session <- function(token) {
  if (!is_token(token)) return(NULL)
  session <- get0(token, envir = .registry, inherits = FALSE)
  if (is.null(session)) return(NULL)
  if (is.function(session$isClosed) && isTRUE(session$isClosed())) return(NULL)
  session
}

# Wrap the user's server function so each session registers before it runs.
# The wrapper always takes `session`; the user's function gets the same
# arguments Shiny would give it (shiny:::argsForServerFunc()).
wrap_server <- function(server = NULL) {
  if (!is.null(server) && !is.function(server)) {
    stop("`server` must be a Shiny server function or NULL.", call. = FALSE)
  }
  params <- if (is.null(server)) character() else names(formals(server))
  function(input, output, session) {
    register_session(session)
    if (is.null(server)) return(invisible())
    args <- list(input = input, output = output)
    if ("clientData" %in% params) args$clientData <- session$clientData
    if ("session" %in% params) args$session <- session
    do.call(server, args)
  }
}

#' The Shiny session bound to an API request
#'
#' Call this inside a plumber endpoint to get the session of the browser tab
#' that made the request. The tab's page sends its session token in the
#' `X-Spigot-Session` header, and spigot binds the request to the session
#' before the endpoint runs. Use the session to read per-tab state
#' (`session$userData`, or reactive values with [shiny::isolate()]).
#'
#' With `spigot_app(require_session = TRUE)` (the default), requests without
#' a live session never reach the endpoint, so the result is never `NULL`.
#'
#' @param req The `req` argument of a plumber endpoint.
#' @return The `ShinySession`, or `NULL` when the request is not bound to one.
#' @export
#' @examples
#' \dontrun{
#' #* @get /visits
#' function(req) {
#'   s <- spigot::spigot_session(req)
#'   s$userData$visits <- sum(s$userData$visits, 1)
#'   list(visits = s$userData$visits)
#' }
#' }
spigot_session <- function(req) {
  if (!is.environment(req) || is.null(req[["REQUEST_METHOD"]])) {
    stop("`req` must be the request object plumber passes to an endpoint.", call. = FALSE)
  }
  req[["spigot_session"]]
}
