# The example's API. `shared` is defined in app.R: spigot_app() evaluates this
# file in app.R's environment.

#* The count and the number of open tabs. A plain HTTP read.
#* @get /state
function() {
  list(count = shared$count, tabs = shared$tabs)
}

#* Add `by` (1 to 10) to the count, tell every tab, and tell this tab's
#* server function.
#* @post /increment
function(req, res, by = 1) {
  by <- suppressWarnings(as.integer(by))
  if (length(by) != 1 || is.na(by) || by < 1 || by > 10) {
    res$status <- 400L
    return(list(error = "by must be a whole number from 1 to 10"))
  }
  shared$count <- shared$count + by

  # Push: every open tab, this one included, gets the new count.
  spigot_broadcast("count", list(count = shared$count, by = by))
  # Bridge: this tab's server function sees input$clicked change.
  spigot_trigger(spigot_session(req), "clicked", by)

  list(count = shared$count)
}
