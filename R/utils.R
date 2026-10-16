`%||%` <- function(x, y) if (is.null(x)) y else x

# Escape a literal string for use inside a regular expression.
regex_escape <- function(x) gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)

is_string <- function(x) is.character(x) && length(x) == 1 && !is.na(x)

is_flag <- function(x) is.logical(x) && length(x) == 1 && !is.na(x)

# Call `f` the way Shiny calls a ui function: with the request if it takes
# an argument, else with none.
call_with_req <- function(f, req) if (length(formals(f))) f(req) else f()
