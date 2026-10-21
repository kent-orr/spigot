# Fixture for test-launch.R: an app directory that uses every part of one a
# launch mode can leave out: a template file, a plumber file, a www/ file and
# a helper in R/.
spigot::spigot_app(pages = spigot::spigot_page("index.html"), api = "api.R",
                   require_session = FALSE)
