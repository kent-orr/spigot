# Package index

## Build an app

- [`spigot_app()`](https://kent-orr.github.io/spigot/reference/spigot_app.md)
  : Create a Shiny app with a plumber API mounted inside it
- [`spigot_page()`](https://kent-orr.github.io/spigot/reference/spigot_page.md)
  : A page rendered from a whisker template
- [`spigot_api()`](https://kent-orr.github.io/spigot/reference/spigot_api.md)
  : Build the API router

## Sessions, push and reactivity

Use these inside endpoints and server functions.

- [`spigot_session()`](https://kent-orr.github.io/spigot/reference/spigot_session.md)
  : The Shiny session bound to an API request
- [`spigot_emit()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  [`spigot_broadcast()`](https://kent-orr.github.io/spigot/reference/spigot_emit.md)
  : Push an event to browser tabs
- [`spigot_trigger()`](https://kent-orr.github.io/spigot/reference/spigot_trigger.md)
  : Set a Shiny input from an endpoint

## Helpers

- [`spigot_json()`](https://kent-orr.github.io/spigot/reference/spigot_json.md)
  : Serialise a value to JSON the spigot way
- [`spigot_dependency()`](https://kent-orr.github.io/spigot/reference/spigot_dependency.md)
  : The spigot.js browser client as an HTML dependency
- [`run_example()`](https://kent-orr.github.io/spigot/reference/run_example.md)
  : Run a bundled example app
