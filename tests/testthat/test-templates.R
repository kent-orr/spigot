# The template search path (spigot_app(templates =)) and partials
# (spigot_app(partials =)), unit level. Pages using them are tested in
# test-page.R.

# ---- template_loader() ---------------------------------------------------------------

test_that("template_loader() searches its dirs in order; the first one wins", {
  root <- local_tree(c("one/b.html" = "one b", "two/a.html" = "two a", "two/b.html" = "two b"))
  load <- template_loader(c("one", "two"), root)
  expect_identical(load("a.html"), "two a")
  expect_identical(load("b.html"), "one b")
})

test_that("a file in the search path is found by its basename, in order", {
  root <- local_tree(c("extra/base.html" = "extra base", "one/base.html" = "one base"))
  expect_identical(template_loader(c("extra/base.html", "one"), root)("base.html"), "extra base")
  expect_identical(template_loader(c("one", "extra/base.html"), root)("base.html"), "one base")
})

test_that("a name is also a path relative to root, tried last", {
  root <- local_tree(c("pages/p.html" = "root p", "one/pages/p.html" = "one p",
                       "q.html" = "root q"))
  load <- template_loader("one", root)
  expect_identical(load("pages/p.html"), "one p")
  expect_identical(load("q.html"), "root q")
  expect_identical(template_loader(NULL, root)("pages/p.html"), "root p")
})

test_that("an absolute path is read as it is", {
  other <- local_tree(c("abs.html" = "absolute"))
  expect_identical(template_loader(NULL, local_tree(character()))(file.path(other, "abs.html")),
                   "absolute")
})

test_that("a miss names the file and every place it looked", {
  root <- local_tree(c("one/x.html" = "x", "two/y.html" = "y"))
  load <- template_loader(c("one", "two"), root)
  err <- expect_error(load("nope.html"), "Can't find the template file \"nope.html\"")
  for (where in c(file.path(root, "one"), file.path(root, "two"), root)) {
    expect_match(conditionMessage(err), where, fixed = TRUE)
  }
  expect_error(load("nope.html", "partial \"nav\""),
               "Can't find the partial \"nav\" file \"nope.html\"")
  expect_error(load("one"), "Can't find") # a directory is not a template
})

test_that("every entry of the search path must exist", {
  root <- local_tree(c("one/x.html" = "x"))
  expect_error(template_loader(c("one", "gone"), root),
               paste0("`templates`.*\"gone\".*", regex_escape(root)))
})

test_that("templates are read as UTF-8", {
  root <- local_tree(character())
  writeLines(enc2utf8("Größe ✓"), file.path(root, "u.html"), useBytes = TRUE)
  out <- template_loader(NULL, root)("u.html")
  expect_identical(Encoding(out), "UTF-8")
  expect_identical(out, enc2utf8("Größe ✓"))
})

# ---- partials ------------------------------------------------------------------------

test_that("a partials dir gives one partial per file, named without its extension", {
  root <- local_tree(c("parts/nav.html" = "<nav>n</nav>", "parts/foot.mustache" = "<p>f</p>",
                       "parts/.hidden" = "h", "parts/sub/x.html" = "x"))
  expect_identical(read_partials_dir(file.path(root, "parts")),
                   list(foot = "<p>f</p>", nav = "<nav>n</nav>"))
})

test_that("two files for one partial name are an error", {
  root <- local_tree(c("parts/nav.html" = "a", "parts/nav.mustache" = "b"))
  expect_error(read_partials_dir(file.path(root, "parts")),
               "\"nav\".*nav.html.*nav.mustache")
})

test_that("app partials are a dir or a named list of text and files", {
  root <- local_tree(c("parts/nav.html" = "<nav>dir</nav>", "foot.html" = "<p>file</p>"))
  load <- template_loader(NULL, root)
  expect_identical(app_partials(NULL, root, load), list())
  expect_identical(app_partials("parts", root, load), list(nav = "<nav>dir</nav>"))
  expect_identical(app_partials(list(nav = "<nav>text</nav>", foot = "foot.html"), root, load),
                   list(nav = "<nav>text</nav>", foot = "<p>file</p>"))
})

test_that("app partials refuse unnamed lists, missing dirs and non-strings", {
  root <- local_tree(c("parts/nav.html" = "n"))
  load <- template_loader(NULL, root)
  expect_error(app_partials(list("parts"), root, load), "unique name")
  expect_error(app_partials(c("parts", "parts"), root, load), "`partials` must be")
  expect_error(app_partials("gone", root, load), "\"gone\".*does not exist")
  expect_error(app_partials(list(nav = 1), root, load), "partials")
})

test_that("merge_partials(): a page's partials win over the app's", {
  expect_identical(merge_partials(list(nav = "app nav", foot = "app foot"),
                                  list(nav = "page nav", side = "page side")),
                   list(nav = "page nav", side = "page side", foot = "app foot"))
  expect_identical(merge_partials(list(), list(a = "x")), list(a = "x"))
  expect_identical(merge_partials(list(a = "x"), list()), list(a = "x"))
})
