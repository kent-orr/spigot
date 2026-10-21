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

`value` itself never leaves R: `input[[name]]` is
[`identical()`](https://rdrr.io/r/base/identical.html) to `value`, so
data frames, factors, dates, `NA` and objects JSON cannot hold arrive
unchanged. Every trigger fires the observers, even with the same value
as the last one. Called with a module's `session`, `name` is namespaced
like the module's own inputs. See
[`vignette("reactivity", package = "spigot")`](https://kent-orr.github.io/spigot/articles/reactivity.md)
for how and when it runs.

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
