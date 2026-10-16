# Fixture for test-push.R. Run by start_app() with spigot loaded.
library(shiny)

ping_me <- function(req) {
  s <- spigot::spigot_session(req)
  spigot::spigot_emit(s, "ping", list(to = "me", from = s$token))
  list(ok = TRUE)
}

ping_all <- function(req) {
  s <- spigot::spigot_session(req)
  n <- spigot::spigot_broadcast("ping", list(to = "all", from = s$token))
  list(sent = n)
}

ping_others <- function(req) {
  s <- spigot::spigot_session(req)
  n <- spigot::spigot_broadcast("ping", list(to = "others", from = s$token), except = s)
  list(sent = n)
}

# A chat room: each session's room lives in its userData.
join <- function(req, room) {
  spigot::spigot_session(req)$userData$room <- room
  list(room = room)
}

say <- function(req, text) {
  room <- spigot::spigot_session(req)$userData$room
  n <- spigot::spigot_broadcast("chat", list(room = room, text = text),
                                filter = function(s) identical(s$userData$room, room))
  list(sent = n)
}

shapes <- function(req) {
  spigot::spigot_emit(spigot::spigot_session(req), "shapes", list(
    one = I(1),
    scalar = 1,
    na = NA,
    empty = character(0),
    rows = data.frame(a = 1:2, b = c("x", NA)),
    obj = list(k = "v", nested = list(deep = I("d")))
  ))
  list(ok = TRUE)
}

api <- spigot::spigot_api() |>
  plumber::pr_post("/ping-me", ping_me) |>
  plumber::pr_post("/ping-all", ping_all) |>
  plumber::pr_post("/ping-others", ping_others) |>
  plumber::pr_post("/join", join) |>
  plumber::pr_post("/say", say) |>
  plumber::pr_post("/shapes", shapes)

spigot::spigot_app(pages = fluidPage(tags$p("spigot-push-fixture")), api = api)
