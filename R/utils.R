`%||%` <- function(x, y) if (is.null(x)) y else x

# Escape a literal string for use inside a regular expression.
regex_escape <- function(x) gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)
