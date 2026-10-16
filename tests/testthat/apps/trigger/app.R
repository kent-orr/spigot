# Fixture for test-trigger.R. Run by start_app() with spigot loaded.
library(shiny)

# Values that JSON cannot carry. spigot_trigger() must deliver them to
# input$shapes exactly.
shapes_value <- function() {
  list(
    one = I(1),
    na = NA,
    rows = data.frame(a = 1:2, b = c("x", NA)),
    fac = factor(c("lo", "hi"), levels = c("lo", "hi")),
    date = as.Date("2026-10-16"),
    nested = list(list(1, "a"), list(2, "b"))
  )
}

cart_add <- function(req) {
  spigot::spigot_trigger(spigot::spigot_session(req), "cart", req$body$value)
  list(ok = TRUE)
}

shapes <- function(req) {
  spigot::spigot_trigger(spigot::spigot_session(req), "shapes", shapes_value())
  list(ok = TRUE)
}

api <- spigot::spigot_api() |>
  plumber::pr_post("/cart/add", cart_add) |>
  plumber::pr_post("/shapes", shapes)

server <- function(input, output, session) {
  observeEvent(input$cart, {
    spigot::spigot_emit(session, "cart:observed", input$cart)
  })
  observeEvent(input$shapes, {
    spigot::spigot_emit(session, "shapes:observed", list(
      identical = identical(input$shapes, shapes_value())
    ))
  })
}

spigot::spigot_app(pages = fluidPage(tags$p("spigot-trigger-fixture")),
                   server = server, api = api)
