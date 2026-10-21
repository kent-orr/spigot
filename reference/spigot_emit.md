# Push an event to browser tabs

`spigot_emit()` sends an event to one tab: the session from
[`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md)
in an endpoint, or the `session` of a Shiny server function.
`spigot_broadcast()` sends it to every open tab of the app. In the page,
`spigot.on(event, function (data, event) { ... })` receives it.

## Usage

``` r
spigot_emit(session, event, data = NULL)

spigot_broadcast(event, data = NULL, except = NULL, filter = NULL)
```

## Arguments

- session:

  A Shiny session, or `NULL`.

- event:

  Event name, a non-empty string such as `"cart:changed"`.

- data:

  Value to send; `NULL` sends `null`.

- except:

  For `spigot_broadcast()`: a session, or a list of sessions, not to
  send to. Pass the endpoint's own session to reach everyone but the
  caller. A module's `session` stands for its whole tab. `NULL` skips
  nobody.

- filter:

  For `spigot_broadcast()`: `NULL`, or a function that takes a session
  and returns `TRUE` to send to it or `FALSE` to skip it, e.g.
  `function(s) identical(s$userData$room, "red")`. It is called for
  every open session before anything is sent, so if it fails, nothing is
  sent.

## Value

`spigot_emit()`: invisibly, `TRUE` if the event was sent, `FALSE` (with
a warning) when `session` is `NULL`. `spigot_broadcast()`: invisibly,
the number of sessions it was sent to.

## Details

`data` is serialised with
[`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md),
so it arrives in the browser in the same shape as an API response would:
length-1 vectors become scalars (wrap them in
[`I()`](https://rdrr.io/r/base/AsIs.html) to keep an array), `NA`
becomes `null` and data frames become arrays of row objects.

Events go over the tab's Shiny websocket as soon as they are emitted. An
event emitted by an endpoint can reach the page *before* the endpoint's
HTTP response does. See
[`vignette("reactivity", package = "spigot")`](https://kent-orr.github.io/spigot/articles/reactivity.md).

## Examples

``` r
if (FALSE) { # \dontrun{
#* @post /cart/add
function(req, sku) {
  s <- spigot::spigot_session(req)
  cart <- add_to_cart(s$userData$cart_id, sku)
  spigot::spigot_emit(s, "cart:changed", cart)
  cart
}

# In the page:
# spigot.on("cart:changed", function (cart) { renderCart(cart); });

# A chat room: tell everyone else in the sender's room.
#* @post /chat/say
function(req, text) {
  s <- spigot::spigot_session(req)
  room <- s$userData$room
  spigot::spigot_broadcast("chat:message", list(room = room, text = text),
    except = s, filter = function(x) identical(x$userData$room, room))
}
} # }
```
