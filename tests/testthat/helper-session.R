# fake_session(): the parts of a ShinySession that spigot uses. An environment,
# so identity (identical()) and mutation behave like the real R6 object.

random_token <- function() {
  paste(sample(c(0:9, letters[1:6]), 32, replace = TRUE), collapse = "")
}

fake_session <- function(token = random_token()) {
  ended <- FALSE
  callbacks <- list()
  sent <- list()
  s <- new.env(parent = emptyenv())
  s$token <- token
  s$userData <- new.env(parent = emptyenv())
  s$sendCustomMessage <- function(type, message) {
    sent[[length(sent) + 1L]] <<- list(type = type, message = message)
    invisible()
  }
  s$onSessionEnded <- function(callback) {
    callbacks[[length(callbacks) + 1L]] <<- callback
    invisible(function() NULL)
  }
  s$isClosed <- function() ended
  # Test controls, not part of ShinySession.
  s$end <- function() {
    ended <<- TRUE
    for (cb in callbacks) cb()
    invisible()
  }
  s$sent <- function() sent
  s$callbacks <- function() length(callbacks)
  s
}

# A registered fake session that is ended when the calling test finishes.
local_session <- function(token = random_token(), env = parent.frame()) {
  s <- fake_session(token)
  register_session(s)
  withr::defer(s$end(), envir = env)
  s
}

# Request headers that bind a request to `s`.
session_header <- function(s) list(`X-Spigot-Session` = s$token)
