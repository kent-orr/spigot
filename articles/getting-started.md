# Getting started

spigot lets you build a Shiny app the way you would build a small
website: pages are hand-written HTML and JavaScript, and the server side
is a set of [plumber](https://www.rplumber.io/) endpoints. spigot mounts
the plumber router inside the Shiny app, so the pages and the API share
one process, one origin and one port. Shiny still hosts the app
(locally, on Shiny Server or on Posit Connect), gives each browser tab a
session, and keeps a websocket open to it.

    Browser tab ──HTTP fetch──▶ /api/*  ──▶ plumber router ─┐
         ▲                                                  │ same R process,
         │                                                  │ same memory
         └──websocket (Shiny session)◀── observers/push ◀───┘

The API is for the app’s own pages, not for other clients. By default it
answers only requests that carry the session token of an open tab of the
app.

This vignette walks through two of the examples that ship with spigot:
`minimal`, one page and four endpoints, and `site`, a three-page site
with shared templates and an endpoint that runs its work in another
process.
[`vignette("reactivity", package = "spigot")`](https://kent-orr.github.io/spigot/articles/reactivity.md)
covers the third example, `live`, and pushing data to pages.

## Installation

``` r

# install.packages("remotes")
remotes::install_github("kent-orr/spigot")
```

Run any example with
[`run_example()`](https://kent-orr.github.io/spigot/reference/run_example.md):

``` r

spigot::run_example("minimal")
```

## The minimal example

An app is a folder with an `app.R`. The `minimal` example’s folder
holds:

    minimal/
    ├── app.R        # spigot_app(): the page and the API
    ├── api.R        # plumber endpoints, served under /api
    ├── index.html   # the page
    └── www/         # files served as they are
        ├── app.js
        └── style.css

### `app.R`

``` r

# spigot "minimal" example: one hand-written page calling a plumber API that
# runs inside this Shiny app, on the same origin and port.
#
# Run it with spigot::run_example("minimal").
library(spigot)

spigot_app(
  # A full HTML document. spigot adds Shiny's scripts and spigot.js to its
  # <head>.
  pages = spigot_page("index.html"),
  # The API is a plain plumber file, served under /api.
  api = "api.R"
)
```

[`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
returns an ordinary Shiny app object, so `shiny::runApp("minimal")`,
Shiny Server and Posit Connect all run it like any other app. Its
arguments:

- `pages`: one page, served at `/`, or a named list of pages keyed by
  path.
- `api`: a plumber file, or a router you built in code with
  [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md).
- `prefix`: where the API is mounted; `"/api"` by default.
- `server`: an optional Shiny server function, for push and reactivity.
- `require_session`: `TRUE` by default; see [Sessions](#sessions) below.

### `api.R`: the endpoints

`api.R` is a plain plumber file. Annotate a function with
`#* @get /path` (or `@post`, `@put`, `@delete`), and its arguments come
from the query string and the JSON body.

``` r

# The example's API. Ordinary plumber annotations; spigot mounts the router at
# /api and serialises results with spigot_json().

#* Greet someone. A GET with a query parameter.
#* @get /hello
function(name = "world") {
  list(message = sprintf("Hello, %s!", name), at = Sys.time())
}

#* Echo a JSON body back. Shows request parsing and response serialisation.
#* @post /echo
function(req) {
  list(received = req$body, received_at = Sys.time())
}

#* Summarise n random normal draws. A data frame becomes an array of row
#* objects; bad input gets a 400 with a JSON error.
#* @get /summary
function(res, n = "1000") {
  n <- suppressWarnings(as.integer(n))
  if (is.na(n) || n < 1 || n > 1e5) {
    res$status <- 400L
    return(list(error = "n must be a whole number from 1 to 100000"))
  }
  x <- stats::rnorm(n)
  p <- c(0, 0.25, 0.5, 0.75, 1)
  list(
    n = n,
    mean = mean(x),
    sd = stats::sd(x),
    quantiles = data.frame(p = p, value = unname(stats::quantile(x, p)))
  )
}

#* Wait, then answer, without blocking the R process: the endpoint returns a
#* promise that a later() timer resolves. Other requests are served meanwhile.
#* (For real work in another process, use promises::future_promise().)
#* @get /slow
function(seconds = "2") {
  secs <- min(max(suppressWarnings(as.numeric(seconds)), 0.1, na.rm = TRUE), 10)
  started <- Sys.time()
  promises::promise(function(resolve, reject) {
    later::later(function() {
      resolve(list(waited = secs, started = started, finished = Sys.time()))
    }, delay = secs)
  })
}
```

Replies are JSON, serialised by
[`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md):
length-1 vectors become scalars, `NA` becomes `null`, and a data frame
becomes an array of row objects. Wrap a value in
[`I()`](https://rdrr.io/r/base/AsIs.html) to keep a length-1 vector as
an array. Setting `res$status` sends another status code, and the page’s
code can read the JSON body of the error.

Request bodies are parsed by plumber as usual: JSON, forms and multipart
uploads. For a binary body, such as a file sent as a `Blob`, give the
endpoint `#* @parser octet`; plumber’s default parsers would try to read
it as text.

### `index.html`: the page

`spigot_page("index.html")` reads a complete HTML document. spigot adds
jQuery, Shiny’s JavaScript and `spigot.js` to its `<head>` when it
serves the page, so the template needs no script tags for them. It needs
only a `</head>` tag, and loads its own files from `www/` with relative
URLs (`style.css`, `app.js`).

The template is a [whisker](https://github.com/edwindj/whisker)
(Mustache) template; `data` fills it in. The minimal page has no `{{ }}`
tags; the `site` example below uses them.

### `www/app.js`: calling the API

`spigot.js` defines `spigot.get()`, `spigot.post()`, `spigot.put()` and
`spigot.del()`. Paths are relative to the API, so
`spigot.get("hello", {name: "Ada"})` requests `api/hello?name=Ada`
relative to the page, which keeps working when the app is served under a
subpath. Each call returns a promise of the parsed JSON reply:

``` js
const reply = await spigot.get("hello", { name: "Ada" });
reply.message;   // "Hello, Ada!"

try {
  await spigot.get("summary", { n: 0 });
} catch (err) {
  // A non-2xx reply, or no reply at all (err.status is then 0).
  err.status;    // 400
  err.message;   // "n must be a whole number from 1 to 100000": the JSON `error` field
  err.body;      // the whole parsed reply
}
```

The example’s page script wraps these calls to show each outcome:

``` js
// The page's only script. It calls the mounted API with spigot.js, which
// spigot_app() adds to every page: spigot.get() and spigot.post() take paths
// relative to the API ("hello" means api/hello, relative to this page, so the
// app also works under a subpath on Shiny Server or Posit Connect), send this
// tab's Shiny session token, and wait for the session if it has not started.
// They resolve with the parsed JSON reply and reject with a SpigotError
// ({status, message, body}) for any non-2xx reply.

// Run one call and describe the outcome for show().
async function call(label, promise) {
  const t0 = performance.now();
  const ms = () => Math.round(performance.now() - t0);
  try {
    const data = await promise;
    return { label, ok: true, outcome: "OK", ms: ms(), data };
  } catch (err) {
    if (!(err instanceof spigot.SpigotError)) throw err;
    // status 0 means no reply: a timeout or a network failure.
    const outcome = err.status ? String(err.status) : "no reply";
    return { label, ok: false, outcome, ms: ms(), data: err.body ?? err.message };
  }
}

function show(el, r) {
  el.textContent = `${r.label}  →  ${r.outcome}  (${r.ms} ms)\n\n` +
    (typeof r.data === "string" ? r.data : JSON.stringify(r.data, null, 2));
  el.classList.toggle("err", !r.ok);
}

function showError(el, err) {
  el.textContent = err.message;
  el.classList.add("err");
}

const $ = (id) => document.getElementById(id);

$("hello-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const name = $("hello-name").value;
  show($("hello-out"), await call("GET api/hello", spigot.get("hello", { name })));
});

$("echo-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("echo-out");
  let body;
  try { body = JSON.parse($("echo-body").value); }
  catch (err) { showError(out, new Error("the box does not hold valid JSON")); return; }
  show(out, await call("POST api/echo", spigot.post("echo", body)));
});

$("summary-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const n = $("summary-n").value;
  show($("summary-out"), await call("GET api/summary", spigot.get("summary", { n })));
});

// The async demo appends to a running log.
const slowLog = [];
function logLine(line) {
  slowLog.push(`${new Date().toLocaleTimeString()}  ${line}`);
  $("slow-out").textContent = slowLog.slice(-12).join("\n");
  $("slow-out").classList.remove("err");
}

$("slow-btn").addEventListener("click", async () => {
  logLine("slow: sent, waiting 3 s ...");
  const r = await call("slow", spigot.get("slow", { seconds: 3 }));
  logLine(`slow: ${r.outcome} after ${r.ms} ms`);
});

$("ping-btn").addEventListener("click", async () => {
  const r = await call("ping", spigot.get("hello", { name: "ping" }));
  logLine(`ping: ${r.outcome} after ${r.ms} ms`);
});
```

[`vignette("client", package = "spigot")`](https://kent-orr.github.io/spigot/articles/client.md)
documents the whole client.

### Sessions

Each browser tab is a Shiny session. `spigot.js` waits for it to start,
then sends its token with every request in an `X-Spigot-Session` header,
and spigot binds the request to that session. An endpoint gets the
session with `spigot_session(req)`, and can keep per-tab state in
`session$userData`:

``` r

#* @get /visits
function(req) {
  s <- spigot::spigot_session(req)
  s$userData$visits <- sum(s$userData$visits, 1)
  list(visits = s$userData$visits)
}
```

With `require_session = TRUE`, the default, a request without the token
of an open tab gets a `401`, so `curl` and other sites cannot call the
API. Use `require_session = FALSE` for an API that should also answer
those requests;
[`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md)
then returns `NULL` for them. Whatever the setting, requests from pages
on another origin get a `403`.

## The site example

`site` is a small site about R’s `mtcars` data with three pages: a home
page, a table of the cars, and a page that fits a regression. It shows
templates with data, shared partials, and an endpoint whose work runs in
another R process.

    site/
    ├── app.R
    ├── api.R
    ├── pages/      # one template per page
    │   ├── index.html
    │   ├── cars.html
    │   └── model.html
    ├── partials/   # shared by every page
    │   ├── head.html
    │   ├── nav.html
    │   └── footer.html
    └── www/
        ├── site.css
        ├── cars.js
        └── model.js

``` r

# spigot "site" example: a small multi-page site about R's mtcars data.
#
# * Three pages, each a whisker template in pages/, sharing the partials in
#   partials/ (the <head>, the nav bar and the footer).
# * The /cars page is rendered in R with every row; its filter form then
#   calls the API and redraws the table in the browser.
# * The /model page calls an endpoint that bootstraps a regression in a
#   future worker, another R process, so the app keeps serving other tabs.
#
# Run it with spigot::run_example("site"). It needs the future package.
library(spigot)

# The fit endpoint hands its work to background R processes.
future::plan(future::multisession, workers = 2)
shiny::onStop(function() future::plan(future::sequential))

cars <- data.frame(model = rownames(datasets::mtcars), datasets::mtcars, row.names = NULL)
predictors <- c(
  wt = "Weight (1000 lbs)", hp = "Horsepower", disp = "Displacement (cu. in.)",
  qsec = "Quarter-mile time (s)", drat = "Rear axle ratio"
)

# A page of the site: its template, the shared partials, and its data. `key`
# tells the nav partial which link is the current page. The data never
# changes, so each page is rendered once and cached.
page <- function(file, key, title, data = list()) {
  spigot_page(
    file.path("pages", file),
    data = c(list(title = title, page = stats::setNames(list(TRUE), key)), data),
    partials = list(
      head = "partials/head.html",
      nav = "partials/nav.html",
      footer = "partials/footer.html"
    ),
    cache = TRUE
  )
}

spigot_app(
  pages = list(
    "/" = page("index.html", "home", "Home", list(
      n = nrow(cars),
      predictors = length(predictors)
    )),
    "/cars" = page("cars.html", "cars", "Cars", list(
      rows = unname(whisker::rowSplit(cars[c("model", "mpg", "cyl", "hp", "wt")]))
    )),
    "/model" = page("model.html", "model", "Model", list(
      predictors = Map(function(name, label) list(name = name, label = label),
                       names(predictors), unname(predictors), USE.NAMES = FALSE)
    ))
  ),
  api = "api.R"
)
```

### Several pages

`pages` is a named list keyed by path. A request for `/cars/` is
redirected to `/cars`, and a path that is neither a page nor a file in
`www/` gets a 404 page. Pages can also be nested (`"/docs/intro"`); see
[`?spigot_page`](https://kent-orr.github.io/spigot/reference/spigot_page.md)
for how their relative URLs resolve.

A top-level page can also be any Shiny UI, such as a `fluidPage()`, so a
classic Shiny page can sit next to hand-written ones.

### Templates, data and partials

Each page’s `data` is a list for its template. `{{title}}` inserts a
value with HTML escaped, so data can never inject markup or R code,
`{{#rows}} ... {{/rows}}` repeats for each element of a list, and
`{{> nav}}` inserts a partial. Here is the cars page, which R renders
with all 32 rows:

``` html
<!DOCTYPE html>
<html lang="en">
{{> head}}
<body>
  {{> nav}}
  <main>
    <h1>Cars</h1>
    <form id="filter" class="row">
      <label>Model contains <input id="q" autocomplete="off" placeholder="e.g. merc"></label>
      <label>At least <input id="min_mpg" inputmode="decimal" size="4" autocomplete="off"> mpg</label>
      <button type="submit">Filter</button>
      <span class="hint" id="status"></span>
    </form>
    <table id="cars">
      <thead>
        <tr><th>Model</th><th>mpg</th><th>Cylinders</th><th>Horsepower</th><th>Weight</th></tr>
      </thead>
      <tbody>
        {{#rows}}
        <tr data-car="{{model}}"><td>{{model}}</td><td>{{mpg}}</td><td>{{cyl}}</td><td>{{hp}}</td><td>{{wt}}</td></tr>
        {{/rows}}
      </tbody>
    </table>
  </main>
  {{> footer}}
  <script src="cars.js"></script>
</body>
</html>
```

All three pages share the `head`, `nav` and `footer` partials. The nav
marks the current page with `aria-current`, using the `page` value each
page’s data sets:

``` html
<nav class="site-nav">
  <span class="brand">spigot <span>site example</span></span>
  <!-- Relative links: they keep working when the app runs under a subpath. -->
  <a href="./" data-page="home"{{#page.home}} aria-current="page"{{/page.home}}>Home</a>
  <a href="cars" data-page="cars"{{#page.cars}} aria-current="page"{{/page.cars}}>Cars</a>
  <a href="model" data-page="model"{{#page.model}} aria-current="page"{{/page.model}}>Model</a>
</nav>
```

`data` can also be a function of the request, called for each request
(for example, to read the query string). The site’s data never changes,
so its pages use `cache = TRUE` and are rendered once.

### Server-rendered first, then the API

The cars page arrives with every row already in the HTML. Its filter
form then asks the API for the matching rows and redraws the table body,
building elements with `textContent` rather than HTML strings:

``` js
// The table arrives rendered in R. Filtering asks the API for matching rows
// and redraws the table body.

const $ = (id) => document.getElementById(id);
const columns = ["model", "mpg", "cyl", "hp", "wt"];

function draw(rows) {
  const body = $("cars").tBodies[0];
  body.replaceChildren(...rows.map((row) => {
    const tr = document.createElement("tr");
    tr.dataset.car = row.model;
    for (const col of columns) {
      const td = document.createElement("td");
      td.textContent = row[col];
      tr.append(td);
    }
    return tr;
  }));
  $("status").textContent = `${rows.length} of 32 cars`;
}

$("filter").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    const reply = await spigot.get("cars", { q: $("q").value, min_mpg: $("min_mpg").value });
    draw(reply.rows);
  } catch (err) {
    if (!(err instanceof spigot.SpigotError)) throw err;
    $("status").textContent = `Error ${err.status}: ${err.message}`;
  }
});

$("status").textContent = `${$("cars").tBodies[0].rows.length} cars`;
```

### Slow work: `future_promise()`

R runs one thing at a time. While an endpoint runs, the app serves no
other request and no other tab, so anything slower than about a tenth of
a second should not run in the app’s R process. An endpoint can return a
promise instead, and spigot replies when it resolves. The fit endpoint
hands its work to a [future](https://future.futureverse.org/) worker
with
[`promises::future_promise()`](https://rstudio.github.io/promises/reference/future_promise.html):

``` r

# The site's API. `cars` and `predictors` are defined in app.R: spigot_app()
# evaluates this file in app.R's environment.

#* Cars whose model name contains `q` (ignoring case) and that do at least
#* `min_mpg` miles per gallon.
#* @get /cars
function(q = "", min_mpg = "") {
  min_mpg <- suppressWarnings(as.numeric(min_mpg))
  if (length(min_mpg) != 1 || is.na(min_mpg)) min_mpg <- -Inf
  keep <- grepl(tolower(q), tolower(cars$model), fixed = TRUE) & cars$mpg >= min_mpg
  # A data frame becomes an array of row objects.
  list(rows = cars[keep, c("model", "mpg", "cyl", "hp", "wt")])
}

#* Regress mpg on one predictor and bootstrap a 95% interval for the slope.
#* The work runs in a future worker, another R process, so this R process
#* keeps serving other requests while it runs.
#* @post /fit
function(res, x = "wt", reps = 1000) {
  if (!is.character(x) || length(x) != 1 || !x %in% names(predictors)) {
    res$status <- 400L
    return(list(error = paste("x must be one of:", paste(names(predictors), collapse = ", "))))
  }
  reps <- suppressWarnings(as.integer(reps))
  if (length(reps) != 1 || is.na(reps) || reps < 100 || reps > 5000) {
    res$status <- 400L
    return(list(error = "reps must be a whole number from 100 to 5000"))
  }

  # Only these values are sent to the worker.
  data <- cars[c("mpg", x)]
  app_pid <- Sys.getpid()
  promises::future_promise({
    started <- Sys.time()
    slope <- function(d) unname(stats::coef(stats::lm(d$mpg ~ d[[x]]))[2])
    boots <- replicate(reps, slope(data[sample.int(nrow(data), replace = TRUE), ]))
    ci <- unname(stats::quantile(boots, c(0.025, 0.975)))
    list(
      x = x,
      reps = reps,
      slope = list(estimate = slope(data), lower = ci[1], upper = ci[2]),
      seconds = as.numeric(Sys.time() - started, units = "secs"),
      worker_pid = Sys.getpid(),
      app_pid = app_pid
    )
  }, seed = TRUE)
  # The endpoint returns the promise; spigot sends the reply when it resolves.
}
```

`app.R` starts the workers with
`future::plan(future::multisession, workers = 2)`. The worker is another
R process: send it the data it needs, as `data` is here, and keep
sessions,
[`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
and other app state in the main process. To push from a worker’s result,
do it in the promise’s `then()`.
[`vignette("reactivity", package = "spigot")`](https://kent-orr.github.io/spigot/articles/reactivity.md)
has more on this.

## Deploying

A spigot app is a Shiny app: deploy its folder as you would any other.
Some things to know:

- **Subpaths.** Use relative URLs in pages (`href="cars"`,
  `src="logo.png"`); `spigot.get()` and friends already resolve their
  paths relative to the page. Apps then work under a subpath such as
  `https://example.com/apps/site/`.
- **Request size.** Shiny rejects request bodies larger than
  `getOption("shiny.maxRequestSize")`, 5 MB by default, before any R
  code runs. That `413` reply is plain text, not JSON. Raise the limit
  with `spigot_app(max_request_size =)`.
- **Several R processes.** Each R process has its own memory and its own
  sessions. If the server runs several processes for one app (Posit
  Connect can), state kept in R and
  [`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  reach only the tabs served by the same process.
- **Proxies.** The cross-origin check compares the request’s `Origin`
  with its `Host`, or with `X-Forwarded-Host` when a proxy sets it. A
  proxy that rewrites `Host` without setting `X-Forwarded-Host` makes
  every `POST` from the browser fail with `403`.
