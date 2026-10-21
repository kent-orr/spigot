# The model section: a form that fits a regression through the API, with
# static/model/model.js. Mounted at /model in app.R.
model <- spigot::spigot_blueprint(
  pages = page("model.html", "model", "Model", list(
    predictors = Map(function(name, label) list(name = name, label = label),
                     names(predictors), unname(predictors), USE.NAMES = FALSE)
  )),
  templates = "templates/model",
  static = "static/model"
)
