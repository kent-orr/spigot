# Fixture for test-launch.R: an app directory that uses every part of one a
# launch mode can leave out: a template file, a plumber file, a www/ file and
# a helper in R/. static/ is spigot's, served in both modes.
spigot::spigot_app(pages = spigot::spigot_page("index.html"), api = "api.R",
                   static = "static", require_session = FALSE)
