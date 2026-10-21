# shout() is defined in R/shout.R.
#* @get /shout
function(word = "hi") list(word = shout(word))

#* @get /wd
function() list(wd = normalizePath(getwd()))
