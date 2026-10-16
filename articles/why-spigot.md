# Why spigot?

Shiny’s reactive model is a good fit for a dashboard: inputs on one
side, outputs on the other, and R works out what to recompute. It fits
less well once an app starts to behave like a web application, where the
page holds state, the user expects every click to respond at once, and
several people work on the same data at the same time. spigot keeps
Shiny as the host and adds the plain web model next to it: the page is
HTML and JavaScript, and it calls R over HTTP.

There are three reasons to want that.

## 1. Responsive apps without reactive plumbing

In a Shiny app, every interaction makes a round trip through the
reactive graph: the input changes, the server recomputes, and outputs
re-render on the server and are sent back. For a plot, that is what you
want. For an interactive widget whose state lives in the page, it gets
heavy.

Take an editable table. A typical Shiny version needs a reactive value
to hold the data, an observer for cell edits, a proxy so the table can
be updated without a full re-render, and more code to undo an edit that
fails to save:

``` r

server <- function(input, output, session) {
  rows <- reactiveVal(load_rows())
  output$table <- DT::renderDT(rows(), editable = "cell")
  proxy <- DT::dataTableProxy("table")

  observeEvent(input$table_cell_edit, {
    edit <- input$table_cell_edit
    new <- DT::editData(rows(), edit)
    saved <- tryCatch({ save_row(new[edit$row, ]); TRUE }, error = function(e) FALSE)
    if (saved) {
      rows(new)
    } else {
      DT::replaceData(proxy, rows())        # put the old value back
      showNotification("Could not save that change.", type = "error")
    }
  })
}
```

Every edit waits for the server before the page settles. Anything else
that depends on `rows()` is invalidated and recomputes. While R does
that, every other session in the process waits too.

With spigot, the table lives in the page. An edit shows at once, the
save happens in the background, and a failed save is handled where the
edit happened:

``` js
table.addEventListener("change", async (e) => {
  const cell = e.target;                    // an <input> in a table cell
  try {
    await spigot.post(`rows/${cell.dataset.id}`,
                      { field: cell.name, value: cell.value },
                      { timeout: 5000 });
    cell.defaultValue = cell.value;         // saved
  } catch (err) {
    cell.value = cell.defaultValue;         // put the old value back
    flash(cell, err.message);
  }
});
```

``` r

#* @post /rows/<id:int>
function(req, res, id, field, value) {
  row <- tryCatch(save_cell(id, field, value), error = function(e) NULL)
  if (is.null(row)) {
    res$status <- 409L
    return(list(error = "That change could not be saved."))
  }
  row
}
```

The endpoint does only the work the edit needs: no re-rendering and no
invalidation. The page never waits for R to show the user’s own change.
Because a request is just a promise in JavaScript, it is easy to do more
on failure: retry, queue edits while the connection is down, or keep
unsaved changes in `localStorage`.

Shiny is still there when you want it. A page can include Shiny outputs,
and an endpoint can feed the reactive graph with
[`spigot_trigger()`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md)
(see
[`vignette("reactivity", package = "spigot")`](https://kent-orr.github.io/spigot/articles/reactivity.md)).

## 2. A website, on the Shiny server you already have

Shiny’s UI functions produce one page of Bootstrap layout with inputs
and outputs. That is quick to write, but a site with its own design,
real URLs for several pages, or a JavaScript library that wants to own
the page means working against the framework.

spigot pages are ordinary HTML documents. Write them by hand, use
whisker templates and partials for shared layout, and bring any
front-end code you like: plain JavaScript, a charting library, a small
framework, or the output of a bundler. R stays the backend, with access
to your data, models and packages.

The usual way to give a JavaScript front end an R backend is a separate
API server, such as plumber on its own. That is another process to
deploy and keep running, another port to open, a reverse proxy to
configure, cross-origin settings, and a separate story for
authentication. In many organisations, each of those is a request to IT.

spigot needs none of them. The API runs inside the Shiny app, on the
same port and the same origin, and deploys as an ordinary Shiny app to
Shiny Server (including the free open-source edition) or Posit Connect.
Whatever already protects the app, such as Connect’s login, protects the
API too. spigot grew out of exactly this situation: Shiny Server Open
Source was already approved and running, opening another port was not on
the table, and the goal was a site that felt like a normal website
rather than a dashboard.

## 3. Many users, one R process

Every tab of a Shiny app is a session in the same R process, so sessions
can share memory. spigot binds each API request to its session and lets
R push to any of them, which makes multi-user features straightforward:

- **Live chat or comments.** One endpoint receives a message and
  broadcasts it to everyone else in the room:

  ``` r

  #* @post /chat/say
  function(req, text) {
    s <- spigot::spigot_session(req)
    spigot::spigot_broadcast("chat:message", list(text = text, at = Sys.time()),
                             except = s)
  }
  ```

- **Pushed data.** When new data arrives, query it once and push it to
  every open tab, rather than having each session poll with
  [`invalidateLater()`](https://rdrr.io/pkg/shiny/man/invalidateLater.html)
  and run the same query.

- **Presence and collaboration.** Show who else is looking at a record,
  or update a row in everyone’s table when one person saves it. The
  `live` example counts open tabs and shares a counter between them
  (`run_example("live")`).

The same process is also the limit. Broadcasts reach the tabs served by
one R process, and a slow endpoint delays every tab in it. Hand slow
work to a `future` worker (see
[`vignette("reactivity", package = "spigot")`](https://kent-orr.github.io/spigot/articles/reactivity.md)),
and plan for an outside message broker if the app has to run in several
processes.

## When plain Shiny is the better choice

spigot asks you to write HTML and JavaScript. Stay with plain Shiny when
the app is mostly standard inputs and outputs, when it is a quick
analysis rather than a product, or when the people who will maintain it
do not write JavaScript. The two also mix: a spigot app can serve a
[`fluidPage()`](https://rdrr.io/pkg/shiny/man/fluidPage.html) next to
hand-written pages, and a classic Shiny page can call a spigot API.
