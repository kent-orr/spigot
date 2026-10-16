# Set a Shiny input from an endpoint

`spigot_trigger()` sets `input[[name]]` in a tab's Shiny session to
`value`, so the app's reactive code (`observeEvent(input$cart, ...)`,
`reactive()`, outputs) runs as if the page had changed an input. Use it
when an API call should update a live view that the server function
builds. Most endpoints do not need it: return the data, or push it with
[`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md).

## Usage

``` r
spigot_trigger(session, name, value)
```

## Arguments

- session:

  The Shiny session from
  [`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md),
  or a server function's `session`.

- name:

  Input name: a letter, then letters, digits, `_`, `.` or `-`.

- value:

  Any R value.

## Value

`TRUE`, invisibly.

## Details

The input is set the normal Shiny way: spigot asks the page, and the
page calls `Shiny.setInputValue()` with `priority: "event"`. So the
observers run in a regular reactive flush, and every trigger fires them,
even with the same value as the last one. It takes one extra trip over
the websocket, about as long as any input change takes Shiny.

`value` itself never leaves R: the page sends back only an id, and
`input[[name]]` is
[`identical()`](https://rdrr.io/r/base/identical.html) to `value`. Data
frames, factors, dates, `NA` and objects JSON cannot hold arrive
unchanged. The value is kept in the session until the page sends the id
back (or the session ends).

Because the page sets the input, the trigger reaches the observers
*after* the endpoint has returned, and only if the page is open and
loaded spigot.js (every spigot page does). Called with a module's
`session`, `name` is namespaced like the module's own inputs.

## Examples

``` r
if (FALSE) { # \dontrun{
#* @post /cart/add
function(req, sku) {
  s <- spigot::spigot_session(req)
  cart <- add_to_cart(s$userData$cart_id, sku)
  spigot::spigot_trigger(s, "cart", cart)
  list(ok = TRUE)
}

# In the server function:
server <- function(input, output, session) {
  output$total <- renderText(sum(input$cart$price))
}
} # }
```
