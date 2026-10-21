# Static dirs: spigot_app(static =, root =). They are httpuv static paths, so
# httpuv serves them without R, in both launch modes (DECISIONS, M14).

# `root` as a normalized absolute path. A relative `root` is relative to the
# working directory when spigot_app() is called.
resolve_root <- function(root) {
  if (!is_string(root)) {
    stop("`root` must be a directory path, a single string.", call. = FALSE)
  }
  if (!dir.exists(root)) {
    stop("`root` must be an existing directory; \"", root, "\" is not one ",
         "(the working directory is \"", getwd(), "\").", call. = FALSE)
  }
  normalizePath(root)
}

# A named list of normalized dirs keyed by URL path: one dir is served at
# /static, a named list at /<name> each. Relative dirs are relative to `root`.
# `prefix` is the API prefix, which no static path may overlap.
check_static <- function(static, root, prefix = NULL) {
  if (is.null(static) || identical(static, list())) return(list())
  if (is_string(static)) static <- list(static = static)
  if (!is.list(static) || !all(vapply(static, is_string, logical(1)))) {
    stop("`static` must be a directory, or a named list of directories.", call. = FALSE)
  }
  nms <- names(static)
  if (is.null(nms) || anyNA(nms) || any(nms == "")) {
    stop("`static` must be one directory or a named list, such as ",
         "list(js = \"js\") to serve the js directory at /js.", call. = FALSE)
  }
  dup <- nms[duplicated(nms)]
  if (length(dup)) {
    stop("`static` has the name \"", dup[1], "\" more than once.", call. = FALSE)
  }
  bad <- nms[!grepl("^[A-Za-z0-9._~-]+$", nms)]
  if (length(bad)) {
    stop("The `static` name \"", bad[1], "\" must be one URL segment: letters, ",
         "digits, '.', '_', '~' or '-'.", call. = FALSE)
  }
  reserved <- nms[nms %in% reserved_prefixes]
  if (length(reserved)) {
    stop("The `static` name \"", reserved[1], "\" is not allowed: Shiny serves /",
         reserved[1], " itself.", call. = FALSE)
  }
  if (!is.null(prefix)) {
    first <- strsplit(prefix, "/", fixed = TRUE)[[1]][2]
    if (first %in% nms) {
      stop("The static path \"/", first, "\" overlaps the API prefix \"", prefix, "\".",
           call. = FALSE)
    }
  }
  dirs <- vapply(static, function(d) if (is_absolute(d)) d else file.path(root, d), "")
  missing <- which(!dir.exists(dirs))
  if (length(missing)) {
    stop("The static directory \"", static[[missing[1]]], "\" does not exist ",
         "(relative paths are relative to `root`, \"", root, "\").", call. = FALSE)
  }
  stats::setNames(as.list(normalizePath(dirs)), paste0("/", nms))
}

# httpuv static paths: each static dir, and the API prefix excluded so that
# httpuv never answers for it.
httpuv_static_paths <- function(static, prefix) {
  c(lapply(static, httpuv::staticPath),
    stats::setNames(list(httpuv::excludeStaticPath()), prefix))
}
