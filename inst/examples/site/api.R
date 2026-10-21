# The site's API. `car_data` and `predictors` are defined in R/data.R, which
# Shiny loads before app.R; spigot_app() evaluates this file in app.R's
# environment, which sees them.

#* Cars whose model name contains `q` (ignoring case) and that do at least
#* `min_mpg` miles per gallon.
#* @get /cars
function(q = "", min_mpg = "") {
  min_mpg <- suppressWarnings(as.numeric(min_mpg))
  if (length(min_mpg) != 1 || is.na(min_mpg)) min_mpg <- -Inf
  keep <- grepl(tolower(q), tolower(car_data$model), fixed = TRUE) & car_data$mpg >= min_mpg
  # A data frame becomes an array of row objects.
  list(rows = car_data[keep, c("model", "mpg", "cyl", "hp", "wt")])
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
  data <- car_data[c("mpg", x)]
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
