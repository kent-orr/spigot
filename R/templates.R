# The template search path (spigot_app(templates =)) and partials
# (spigot_app(partials =)). Template files are read when the app is built, by
# resolve_page() (DECISIONS, M15).

# function(name, what = "template") returning the text of the template file
# `name`: the first of `dirs` that is a directory holding `name` or a file
# whose basename is `name`, else `name` relative to `root`. An absolute `name`
# is read as it is. Relative `dirs` are relative to `root`.
template_loader <- function(dirs, root) {
  dirs <- as.character(dirs %||% character())
  paths <- file.path(root, dirs)
  paths[is_absolute(dirs)] <- dirs[is_absolute(dirs)]
  gone <- !file.exists(paths)
  if (any(gone)) {
    stop("`templates` has \"", dirs[gone][1], "\", which does not exist ",
         "(relative paths are relative to `root`, \"", root, "\").", call. = FALSE)
  }
  paths <- normalizePath(paths)
  is_dir <- dir.exists(paths)

  function(name, what = "template") {
    if (is_absolute(name)) {
      tried <- name
    } else {
      tried <- paths
      tried[is_dir] <- file.path(paths[is_dir], name)
      tried <- c(tried[is_dir | basename(paths) == name], file.path(root, name))
    }
    found <- tried[file.exists(tried) & !dir.exists(tried)]
    if (!length(found)) {
      looked <- if (!is_absolute(name)) {
        paste0(" (looked in \"", paste(c(paths, root), collapse = "\", \""), "\")")
      }
      stop("Can't find the ", what, " file \"", name, "\"", looked,
           ". Template text must contain '<', '{{' or a line break.", call. = FALSE)
    }
    read_text_file(found[1])
  }
}

read_text_file <- function(path) {
  enc2utf8(paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n"))
}

# One partial per file in `dir`, named by the file name without its
# extension. Hidden files and subdirectories are skipped.
read_partials_dir <- function(dir) {
  files <- list.files(dir, full.names = TRUE)
  files <- files[!dir.exists(files)]
  keys <- sub("\\.[^.]*$", "", basename(files))
  dup <- keys[duplicated(keys)]
  if (length(dup)) {
    stop("The partials directory \"", dir, "\" has more than one file for the partial \"",
         dup[1], "\": ", paste(basename(files[keys == dup[1]]), collapse = " and "), ".",
         call. = FALSE)
  }
  stats::setNames(lapply(files, read_text_file), keys)
}

# spigot_app()'s `partials`: NULL, a directory (relative to `root`), or a
# named list like spigot_page()'s, its files found by `loader`.
app_partials <- function(partials, root, loader) {
  if (is.null(partials)) return(list())
  if (is_string(partials)) {
    dir <- if (is_absolute(partials)) partials else file.path(root, partials)
    if (!dir.exists(dir)) {
      stop("The partials directory \"", partials, "\" does not exist (relative paths are ",
           "relative to `root`, \"", root, "\").", call. = FALSE)
    }
    return(read_partials_dir(normalizePath(dir)))
  }
  if (!is.list(partials)) {
    stop("`partials` must be a directory, or a named list of partials.", call. = FALSE)
  }
  read_partials(check_partials(partials), loader)
}

# Partials as text: text as given, files read by `loader`.
read_partials <- function(partials, loader) {
  out <- lapply(names(partials), function(nm) {
    read_template(partials[[nm]], paste0("partial \"", nm, "\""), loader)
  })
  stats::setNames(out, names(partials))
}

# A page's own partials win over the app's.
merge_partials <- function(app, page) {
  c(page, app[setdiff(names(app), names(page))])
}
