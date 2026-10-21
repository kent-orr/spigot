#* @get /fit
function(req) list(fit = "ok", session = !is.null(spigot::spigot_session(req)))
