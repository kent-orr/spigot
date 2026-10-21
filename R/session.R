# Session registry: Shiny session token -> live ShinySession (PLAN 4.2).
#
# Every session of a spigot app registers here when its server function
# starts and is removed when it ends. The API guard looks the token from the
# X-Spigot-Session header up here to bind a request to its tab.

.registry <- new.env(parent = emptyenv())

# Shiny tokens are createUniqueId(16): 32 lowercase hex characters (F7).
is_token <- function(x) {
  is_string(x) && grepl("^[0-9a-f]{16,}$", x)
}

register_session <- function(session) {
  token <- session$token
  if (!is_token(token)) {
    stop("Cannot register a session without a valid token.", call. = FALSE)
  }
  assign(token, session, envir = .registry)
  session$onSessionEnded(function() prune_session(session))
  invisible(session)
}

# Remove `session` from the registry. Called when it ends, and when a send
# fails: the socket is gone even if Shiny has not noticed.
prune_session <- function(session) {
  token <- session$token
  if (identical(get0(token, envir = .registry, inherits = FALSE), session)) {
    rm(list = token, envir = .registry)
  }
  invisible()
}

is_closed <- function(session) {
  is.function(session$isClosed) && isTRUE(session$isClosed())
}

# The live session for `token`, or NULL.
lookup_session <- function(token) {
  if (!is_token(token)) return(NULL)
  session <- get0(token, envir = .registry, inherits = FALSE)
  if (is.null(session) || is_closed(session)) return(NULL)
  session
}

# Every registered session that is still open. Closed ones are pruned.
live_sessions <- function() {
  sessions <- unname(as.list(.registry, all.names = TRUE))
  closed <- vapply(sessions, is_closed, logical(1))
  for (session in sessions[closed]) prune_session(session)
  sessions[!closed]
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

check_event <- function(event) {
  if (!is_string(event) || !nzchar(event)) {
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
#' HTTP response does. See `vignette("reactivity", package = "spigot")`.
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
  if (!is_session(session)) {
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

  targets <- Filter(function(s) !any(vapply(except, identical, logical(1), s)),
                    live_sessions())
  if (!is.null(filter)) {
    keep <- vapply(targets, function(s) {
      k <- filter(s)
      if (!is_flag(k)) stop("`filter` must return TRUE or FALSE.", call. = FALSE)
      k
    }, logical(1))
    targets <- targets[keep]
  }

  message <- event_message(event, data)
  sent <- vapply(targets, function(s) tryCatch({
    s$sendCustomMessage("spigot:event", message)
    TRUE
  }, error = function(e) {
    prune_session(s)
    FALSE
  }), logical(1))
  invisible(sum(sent))
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

#' Set a Shiny input from an endpoint
#'
#' `spigot_trigger()` sets `input[[name]]` in a tab's Shiny session to
#' `value`, so the app's reactive code (`observeEvent(input$cart, ...)`,
#' `reactive()`, outputs) runs as if the page had changed an input. Use it
#' when an API call should update a live view that the server function
#' builds. Most endpoints do not need it: return the data, or push it with
#' [spigot_emit()].
#'
#' `value` itself never leaves R: `input[[name]]` is `identical()` to
#' `value`, so data frames, factors, dates, `NA` and objects JSON cannot hold
#' arrive unchanged. Every trigger fires the observers, even with the same
#' value as the last one. Called with a module's `session`, `name` is
#' namespaced like the module's own inputs. See
#' `vignette("reactivity", package = "spigot")` for how and when it runs.
#'
#' @param session The Shiny session from [spigot_session()], or a server
#'   function's `session`.
#' @param name Input name: a letter, then letters, digits, `_`, `.` or `-`.
#' @param value Any R value.
#' @return `TRUE`, invisibly.
#' @export
#' @examples
#' \dontrun{
#' #* @post /cart/add
#' function(req, sku) {
#'   s <- spigot::spigot_session(req)
#'   cart <- add_to_cart(s$userData$cart_id, sku)
#'   spigot::spigot_trigger(s, "cart", cart)
#'   list(ok = TRUE)
#' }
#'
#' # In the server function:
#' server <- function(input, output, session) {
#'   output$total <- renderText(sum(input$cart$price))
#' }
#' }
spigot_trigger <- function(session, name, value) {
  if (!is_string(name) || !grepl("^[A-Za-z][A-Za-z0-9_.-]*$", name)) {
    stop("`name` must be an input name: a letter, then letters, digits, ",
         "`_`, `.` or `-`.", call. = FALSE)
  }
  if (is.null(session)) {
    stop("spigot_trigger() needs a session. ",
         "Was the endpoint called without a session token?", call. = FALSE)
  }
  if (!is_session(session)) {
    stop("`session` must be a Shiny session.", call. = FALSE)
  }
  if (is.function(session$ns)) name <- session$ns(name)
  id <- next_trigger_id()
  assign(id, value, envir = trigger_store(session))
  session$sendCustomMessage("spigot:set-input", list(name = name, id = id))
  invisible(TRUE)
}

.trigger <- new.env(parent = emptyenv())
.trigger$n <- 0

next_trigger_id <- function() {
  .trigger$n <- .trigger$n + 1
  format(.trigger$n, scientific = FALSE)
}

# Values waiting for the page to send their id back. Kept in the session's
# userData (a hidden name), so they go when the session does. A module's
# session shares its root's userData.
trigger_store <- function(session) {
  store <- session$userData[[".spigot_triggers"]]
  if (is.null(store)) {
    store <- new.env(parent = emptyenv())
    assign(".spigot_triggers", store, envir = session$userData)
  }
  store
}

# Shiny input handler for "<name>:spigot.ref": the page sent back the id of a
# value spigot_trigger() kept; the input becomes that value. An id this
# session does not hold gives NULL.
resolve_trigger <- function(val, shinysession, name) {
  if (!is_string(val)) return(NULL)
  store <- shinysession$userData[[".spigot_triggers"]]
  if (is.null(store) || !exists(val, envir = store, inherits = FALSE)) return(NULL)
  value <- get(val, envir = store, inherits = FALSE)
  rm(list = val, envir = store)
  value
}
