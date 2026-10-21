# A temporary directory holding `files` (relative path = contents), removed
# when the calling test finishes. Returns its normalized path.
local_tree <- function(files, env = parent.frame()) {
  root <- normalizePath(withr::local_tempdir(.local_envir = env))
  for (f in names(files)) {
    dir.create(dirname(file.path(root, f)), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[f]], file.path(root, f))
  }
  root
}
