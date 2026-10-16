# Chrome for the e2e tests. Uses a browser on the PATH if there is one, else
# the Chrome for Testing headless shell in chromote's cache (DECISIONS.md,
# M0 step 0). Nothing is downloaded here: when no browser is found the test
# is skipped with instructions, or fails if the SPIGOT_REQUIRE_CHROME
# environment variable is "true" (set in CI cells that install Chrome, so
# the e2e tests cannot be skipped there without anyone noticing).

chrome_path <- function() {
  found <- tryCatch(suppressMessages(chromote::find_chrome()), error = function(e) NULL)
  if (length(found) && nzchar(found)) return(found)
  cached <- tryCatch(
    chromote::chrome_versions_list("installed", binary = "chrome-headless-shell"),
    error = function(e) NULL
  )
  if (is.null(cached) || !nrow(cached)) return(NULL)
  path <- utils::tail(cached$path, 1)
  if (file.exists(path)) path else NULL
}

skip_if_no_chrome <- function(path = chrome_path()) {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("chromote")
  if (is.null(path)) {
    if (identical(Sys.getenv("SPIGOT_REQUIRE_CHROME"), "true")) {
      stop("No Chrome found, and SPIGOT_REQUIRE_CHROME is \"true\".", call. = FALSE)
    }
    testthat::skip(paste0(
      "no Chrome found; install one with chromote::local_chrome_version(",
      "\"latest-stable\", binary = \"chrome-headless-shell\")"
    ))
  }
  if (!identical(Sys.getenv("CHROMOTE_CHROME"), path)) Sys.setenv(CHROMOTE_CHROME = path)
  # Ubuntu 23.10+ blocks Chrome's user-namespace sandbox (DECISIONS.md, M0
  # step 0). The browser only loads our own localhost test app.
  if (Sys.info()[["sysname"]] == "Linux" &&
      !"--no-sandbox" %in% chromote::get_chrome_args()) {
    chromote::set_chrome_args(c(chromote::default_chrome_args(), "--no-sandbox"))
  }
  invisible(path)
}

# Evaluate JS in a tab, awaiting promises; returns the value.
js <- function(tab, expr, timeout = 10) {
  r <- tab$Runtime$evaluate(expr, awaitPromise = TRUE, returnByValue = TRUE,
                            timeout_ = timeout)
  if (!is.null(r$exceptionDetails)) {
    stop("JS error: ", r$exceptionDetails$exception$description %||% r$exceptionDetails$text)
  }
  r$result$value
}

# Open `url` in a new tab and wait until the Shiny session has its token.
# The tab is closed when the calling test finishes.
new_tab <- function(url, timeout = 10, env = parent.frame()) {
  tab <- chromote::ChromoteSession$new()
  withr::defer(try(tab$close(), silent = TRUE), envir = env)
  tab$Page$navigate(url)
  ready <- "!!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.config && Shiny.shinyapp.config.sessionId)"
  deadline <- Sys.time() + timeout
  while (!isTRUE(js(tab, ready))) {
    if (Sys.time() > deadline) stop("Shiny session did not start within ", timeout, " s")
    Sys.sleep(0.05)
  }
  tab
}
