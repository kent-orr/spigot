# spigot "live" example: a counter shared by every open tab. It uses all three
# channels between a page and R:
#
# * HTTP: the page reads and changes the count with spigot.get() and
#   spigot.post() (api.R).
# * Push: R sends every open tab the new count with spigot_broadcast(), and
#   the page listens with spigot.on().
# * Bridge: the endpoint also sets an input of the calling tab with
#   spigot_trigger(), so that tab's server function updates a Shiny output
#   on the page.
#
# Run it with spigot::run_example("live"), then open the page in a second tab.
library(shiny)
library(spigot)

# State shared by every tab. It lives in this R process, so the endpoints in
# api.R (evaluated in this environment) and the server function see the same
# values.
shared <- new.env()
shared$count <- 0L
shared$tabs <- 0L

server <- function(input, output, session) {
  # A tab opened or closed: tell every tab how many are open.
  shared$tabs <- shared$tabs + 1L
  spigot_broadcast("tabs", list(tabs = shared$tabs))
  session$onSessionEnded(function() {
    shared$tabs <- shared$tabs - 1L
    spigot_broadcast("tabs", list(tabs = shared$tabs))
  })

  # This tab's own clicks. The increment endpoint sets input$clicked with
  # spigot_trigger(); the page shows output$mine in an element with the
  # class "shiny-text-output".
  mine <- reactiveVal(0L)
  observeEvent(input$clicked, mine(mine() + input$clicked))
  output$mine <- renderText(mine())
}

spigot_app(
  pages = spigot_page("index.html"),
  server = server,
  api = "api.R"
)
