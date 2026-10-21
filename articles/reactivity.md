# Push, reactivity and concurrency

A spigot page can exchange data with R in three ways. Most apps need
only the first.

| Channel | Direction | Use it for | R side | Page side |
|----|----|----|----|----|
| HTTP | page → R → page | Queries, commands, forms, loading data | plumber endpoints | `spigot.get()`, `spigot.post()`, … |
| Push | R → page | Live updates, progress, events another tab caused | [`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md), [`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md) | `spigot.on()` |
| Bridge | HTTP → reactive graph | An API call that should update reactive code in the server function | [`spigot_trigger()`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md) | nothing: spigot.js handles it |

Rules of thumb:

- **Start with HTTP.** A page asks; R answers. Shiny hosts the app and
  gives each tab a session, and that is all most apps need from it.
- **Push when R knows something the page did not ask for**: another user
  changed the data, a long job made progress, a timer fired.
- **Use the bridge only when the server function owns the view**: Shiny
  outputs, or reactive code that should run when an endpoint is called.
  It is optional; nothing else in spigot depends on it.

The `live` example uses all three. Run it with
`spigot::run_example("live")` and open it in two tabs.

## Push: `spigot_emit()` and `spigot_broadcast()`

`spigot_emit(session, event, data)` sends an event to one tab: the
session of the request, from `spigot_session(req)` in an endpoint, or
the `session` of a server function. `spigot_broadcast(event, data)`
sends it to every open tab. The page listens with `spigot.on()`:

``` js
const stop = spigot.on("cart:changed", (cart, event) => renderCart(cart));
// later, if needed:
stop();
```

``` r

#* @post /cart/add
function(req, sku) {
  s <- spigot::spigot_session(req)
  cart <- add_to_cart(s$userData$cart_id, sku)
  spigot::spigot_emit(s, "cart:changed", cart)
  cart
}
```

`data` is serialised with
[`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md),
so it arrives in the page in the same shape as an API reply. Events
travel over the tab’s Shiny websocket.

[`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
takes `except`, sessions to skip, and `filter`, a function of a session
that returns `TRUE` to send to it. Together they cover “tell everyone
else” and rooms:

``` r

#* @post /chat/say
function(req, text) {
  s <- spigot::spigot_session(req)
  room <- s$userData$room
  spigot::spigot_broadcast("chat:message", list(room = room, text = text),
    except = s, filter = function(x) identical(x$userData$room, room))
}
```

Things to know about push:

- **A push can beat the reply.** R sends an event as soon as
  [`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  is called, while the endpoint is still running, so the page can
  receive it before the HTTP reply to the same request. Do not write
  page code that assumes the reply comes first. The `live` example keeps
  the highest count it has seen, whichever message carries it.
- **No replay.** Events that arrive before the page calls `spigot.on()`
  for them are dropped. Register listeners when the script loads, and
  load the current state over HTTP.
- **One R process.**
  [`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  reaches the open tabs served by this R process. If the server runs
  several processes for one app, tabs in other processes do not get the
  event. Pushing across processes needs an outside relay, such as Redis
  or Postgres `LISTEN/NOTIFY`, and spigot does not provide one.
- **Push from the app’s process**: an endpoint, an observer, a
  [`later::later()`](https://later.r-lib.org/reference/later.html)
  callback. A `future` worker is another R process and has no sessions.
  Emit from the promise’s `then()`, which runs in the app’s process.

## The bridge: `spigot_trigger()`

`spigot_trigger(session, name, value)` sets `input[[name]]` in a tab’s
session, so the server function’s reactive code runs as if the page had
changed an input:

``` r

server <- function(input, output, session) {
  mine <- reactiveVal(0L)
  observeEvent(input$clicked, mine(mine() + input$clicked))
  output$mine <- renderText(mine())
}
```

A hand-written page shows a Shiny output with an element that has the
output’s `id` and class, here
`<div id="mine" class="shiny-text-output"></div>`. Shiny binds it as it
would a [`textOutput()`](https://rdrr.io/pkg/shiny/man/textOutput.html).
Other outputs use their own classes: `shiny-html-output` for
[`uiOutput()`](https://rdrr.io/pkg/shiny/man/htmlOutput.html),
`shiny-plot-output` for
[`plotOutput()`](https://rdrr.io/pkg/shiny/man/plotOutput.html), and so
on.

How it behaves:

- **The value never leaves R.** spigot keeps `value` in the session and
  sends the page only an id; the page sets the input to the id and
  spigot swaps the value back in. So `input[[name]]` is
  [`identical()`](https://rdrr.io/r/base/identical.html) to `value`:
  data frames, factors, dates and `NA` arrive unchanged. The value stays
  in the session until the page sends the id back, or the session ends.
- **It runs after the endpoint returns,** in Shiny’s normal reactive
  flush, and only if the tab is open and has loaded spigot.js (every
  spigot page has). It takes one more trip over the websocket, about as
  long as any Shiny input change.
- **Every trigger fires.** Observers run even when the value equals the
  last one.
- **Modules.** Called with a module’s `session`, `name` is namespaced
  like the module’s own inputs.

If you only need the page to show new data, return it or push it; there
is no need to go through the reactive graph.

## The live example

`app.R` keeps the shared state in an environment that the endpoints and
the server function both see, and broadcasts the number of open tabs
when one opens or closes:

``` r

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
```

The increment endpoint uses all three channels: the reply carries the
new count, a broadcast tells every tab, and a trigger tells the calling
tab’s server function.

``` r

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
```

The page’s script listens for both events, loads the current state once,
and calls the API from its buttons:

``` js
// The page's only script. spigot_app() adds spigot.js, which defines spigot.get(),
// spigot.post() and spigot.on().

const $ = (id) => document.getElementById(id);

// The count only goes up, so show the highest value seen. A reply and a push
// can arrive in either order: R sends the push while the endpoint runs, so it
// can reach the page before the reply to the same request.
let shown = -1;
function showCount(n) {
  if (n <= shown) return;
  shown = n;
  $("count").textContent = n;
}

const lines = [];
function log(line) {
  lines.push(`${new Date().toLocaleTimeString()}  ${line}`);
  $("log").textContent = lines.slice(-10).join("\n");
}

// Push: R calls spigot_broadcast() when the count changes or a tab opens or closes.
spigot.on("count", (msg) => {
  showCount(msg.count);
  log(`push  count: ${msg.count} (+${msg.by})`);
});
spigot.on("tabs", (msg) => {
  $("tabs").textContent = msg.tabs;
  log(`push  tabs: ${msg.tabs}`);
});

// HTTP: read the current state once. spigot.get() waits for the Shiny session.
spigot.get("state").then((s) => {
  showCount(s.count);
  $("tabs").textContent = s.tabs;
});

async function add(by) {
  try {
    const reply = await spigot.post("increment", { by });
    showCount(reply.count);
    log(`reply count: ${reply.count}`);
  } catch (err) {
    if (!(err instanceof spigot.SpigotError)) throw err;
    log(`reply ${err.status}: ${err.message}`);
  }
}

$("plus-one").addEventListener("click", () => add(1));
$("plus-five").addEventListener("click", () => add(5));
$("plus-bad").addEventListener("click", () => add(11));
```

## Concurrency

A Shiny app runs in one R process with one thread. **While an endpoint
runs, nothing else in that process does**: no other request, no other
tab’s reactive code, no pushes. A query that takes two seconds makes
every tab wait two seconds.

For anything slower than about 100 ms:

- **Return a promise.** spigot replies when it resolves, and the process
  serves other requests meanwhile.
  [`promises::future_promise()`](https://rstudio.github.io/promises/reference/future_promise.html)
  runs the work in a [future](https://future.futureverse.org/) worker;
  [mirai](https://mirai.r-lib.org/) works too. The `site` example’s fit
  endpoint is a complete example.

  ``` r

  #* @post /report
  function(req, month) {
    s <- spigot::spigot_session(req)
    promises::future_promise({
      build_report(month)          # runs in a worker
    }) |>
      promises::then(function(report) {
        # back in the app's process: sessions and push work here
        spigot::spigot_emit(s, "report:ready", list(month = month))
        report
      })
  }
  ```

- **Send the worker what it needs.** A worker is another R process: it
  has no sessions and none of the app’s in-memory state. Pass data in,
  and use the result in `then()`.

- **Wait without blocking.** To wait for something, resolve a promise
  from [`later::later()`](https://later.r-lib.org/reference/later.html)
  instead of calling
  [`Sys.sleep()`](https://rdrr.io/r/base/Sys.sleep.html). The `minimal`
  example’s `/slow` endpoint does this.

- **Give the page a timeout.**
  `spigot.get(path, query, {timeout: 5000})` rejects with a
  `SpigotError` whose `status` is `0` if no reply arrives within five
  seconds, and aborts the request.
