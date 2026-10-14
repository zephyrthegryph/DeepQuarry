var/global/const/label = "global label"
/proc/probe()
    var/static/const/label = "local label"
    set name = label
    set desc = label
    return label