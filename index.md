# spigot

spigot runs a [plumber](https://www.rplumber.io/) API inside a
[Shiny](https://shiny.posit.co/) app, so you can build the app like a
small website: pages are hand-written HTML and JavaScript, and they call
R endpoints on the same origin and port.

Shiny still hosts the app (locally, on Shiny Server or on Posit
Connect), gives each browser tab a session, and keeps a websocket open
to it. spigot uses that to tie each API request to the tab that sent it,
to push events from R to pages, and, when you want it, to feed API calls
into Shiny’s reactive code.

## Installation

``` r

# install.packages("remotes")
remotes::install_github("kent-orr/spigot")
```

## Example

``` r

library(spigot)

api <- spigot_api() |>
  plumber::pr_get("/hello", function(name = "world") {
    list(message = paste0("Hello, ", name, "!"))
  })

home <- spigot_page('<!DOCTYPE html>
<html>
<head><title>hello</title></head>
<body>
  <button id="go">Say hello</button> <span id="out"></span>
  <script>
    document.getElementById("go").onclick = async () => {
      const reply = await spigot.get("hello", { name: "Ada" });
      document.getElementById("out").textContent = reply.message;
    };
  </script>
</body>
</html>')

shiny::runApp(spigot_app(pages = home, api = api))
```

[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
adds Shiny’s scripts and `spigot.js` to the page. `spigot.get()` calls
`api/hello`, sends the tab’s session token, and resolves with the parsed
JSON reply.

Three larger examples ship with the package:

``` r

run_example("minimal")  # one page, GET and POST, errors, an async endpoint
run_example("live")     # push to every tab, and a Shiny output driven by the API
run_example("site")     # three pages with shared templates, work in a future worker
```

## Learn more

- [Why
  spigot?](https://kent-orr.github.io/spigot/articles/why-spigot.html)
- [Getting
  started](https://kent-orr.github.io/spigot/articles/getting-started.html)
- [Push, reactivity and
  concurrency](https://kent-orr.github.io/spigot/articles/reactivity.html)
- [The browser client:
  spigot.js](https://kent-orr.github.io/spigot/articles/client.html)
- [Function reference](https://kent-orr.github.io/spigot/reference/)
