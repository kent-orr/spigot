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

# Remove `session` from the registry now, without waiting for onSessionEnded.
# Used when a send fails: the socket is gone even if Shiny has not noticed.
prune_session <- function(session) {
  unregister_session(session$token, session)
}

check_event <- function(event) {
  if (!is.character(event) || length(event) != 1 || is.na(event) || !nzchar(event)) {
    stop("`event` must be a single non-empty string.", call. = FALSE)
  }
  invisible(event)
}

# The spigot:event message. The payload travels as a JSON string made by
# spigot_json(), so Shiny's own toJSON() cannot reshape it.
event_message <- function(event, data) {
  list(event = event, json = as.character(spigot_json(data)))
}

#' Push an event to browser tabs
#'
#' `spigot_emit()` sends an event to one tab: the session from
#' [spigot_session()] in an endpoint, or the `session` of a Shiny server
#' function. `spigot_broadcast()` sends it to every open tab of the app.
#' In the page, `spigot.on(event, function (data, event) { ... })` receives it.
#'
#' `data` is serialised with [spigot_json()], so it arrives in the browser in
#' the same shape as an API response would: length-1 vectors become scalars
#' (wrap them in [I()] to keep an array), `NA` becomes `null` and data frames
#' become arrays of row objects.
#'
#' Events go over the tab's Shiny websocket as soon as they are emitted. An
#' event emitted by an endpoint can reach the page *before* the endpoint's
#' HTTP response does. Events sent before the page has called `spigot.on()`
#' for them are dropped.
#'
#' Call these from the app's own R process (an endpoint, an observer, a
#' [later::later()] callback). A `future` worker is another process and has no
#' sessions; emit from the promise's `then()` instead.
#'
#' @param session A Shiny session, or `NULL`.
#' @param event Event name, a non-empty string such as `"cart:changed"`.
#' @param data Value to send; `NULL` sends `null`.
#' @return `spigot_emit()`: invisibly, `TRUE` if the event was sent, `FALSE`
#'   (with a warning) when `session` is `NULL`. `spigot_broadcast()`:
#'   invisibly, the number of sessions it was sent to.
#' @export
#' @examples
#' \dontrun{
#' #* @post /cart/add
#' function(req, sku) {
#'   s <- spigot::spigot_session(req)
#'   cart <- add_to_cart(s$userData$cart_id, sku)
#'   spigot::spigot_emit(s, "cart:changed", cart)
#'   cart
#' }
#'
#' # In the page:
#' # spigot.on("cart:changed", function (cart) { renderCart(cart); });
#'
#' # A chat room: tell everyone else in the sender's room.
#' #* @post /chat/say
#' function(req, text) {
#'   s <- spigot::spigot_session(req)
#'   room <- s$userData$room
#'   spigot::spigot_broadcast("chat:message", list(room = room, text = text),
#'     except = s, filter = function(x) identical(x$userData$room, room))
#' }
#' }
spigot_emit <- function(session, event, data = NULL) {
  check_event(event)
  if (is.null(session)) {
    warning("spigot_emit(): no session, so the \"", event, "\" event was not sent. ",
            "Was the endpoint called without a session token?", call. = FALSE)
    return(invisible(FALSE))
  }
  if (!is.function(session$sendCustomMessage)) {
    stop("`session` must be a Shiny session or NULL.", call. = FALSE)
  }
  session$sendCustomMessage("spigot:event", event_message(event, data))
  invisible(TRUE)
}

#' @param except For `spigot_broadcast()`: a session, or a list of sessions,
#'   not to send to. Pass the endpoint's own session to reach everyone but
#'   the caller. A module's `session` stands for its whole tab. `NULL` skips
#'   nobody.
#' @param filter For `spigot_broadcast()`: `NULL`, or a function that takes a
#'   session and returns `TRUE` to send to it or `FALSE` to skip it, e.g.
#'   `function(s) identical(s$userData$room, "red")`. It is called for every
#'   open session before anything is sent, so if it fails, nothing is sent.
#' @rdname spigot_emit
#' @export
spigot_broadcast <- function(event, data = NULL, except = NULL, filter = NULL) {
  check_event(event)
  except <- check_except(except)
  if (!is.null(filter) && !is.function(filter)) {
    stop("`filter` must be a function of a session, or NULL.", call. = FALSE)
  }

  targets <- list()
  for (token in ls(.registry, all.names = TRUE)) {
    session <- get0(token, envir = .registry, inherits = FALSE)
    if (is.null(session)) next
    if (is.null(lookup_session(token))) {
      prune_session(session)
      next
    }
    if (any(vapply(except, identical, logical(1), session))) next
    if (!is.null(filter)) {
      keep <- filter(session)
      if (!is.logical(keep) || length(keep) != 1 || is.na(keep)) {
        stop("`filter` must return TRUE or FALSE.", call. = FALSE)
      }
      if (!keep) next
    }
    targets[[length(targets) + 1L]] <- session
  }

  message <- event_message(event, data)
  sent <- 0L
  for (session in targets) {
    ok <- tryCatch({
      session$sendCustomMessage("spigot:event", message)
      TRUE
    }, error = function(e) FALSE)
    if (ok) sent <- sent + 1L else prune_session(session)
  }
  invisible(sent)
}

# `except` as a list of root sessions. A module's `session` is a proxy; the
# registry holds the root session, so compare against that.
check_except <- function(except) {
  if (is.null(except)) return(list())
  if (is_session(except)) except <- list(except)
  if (!is.list(except) || is.object(except) || !all(vapply(except, is_session, logical(1)))) {
    stop("`except` must be a session, a list of sessions, or NULL.", call. = FALSE)
  }
  lapply(except, root_session)
}

root_session <- function(session) {
  if (is.function(session$rootScope)) session$rootScope() else session
}

is_session <- function(x) {
  (is.environment(x) || inherits(x, "R6")) && is.function(x$sendCustomMessage)
}
