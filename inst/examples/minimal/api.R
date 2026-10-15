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
