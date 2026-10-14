/world
    name = "Hidden marker compile oracle"

/datum/marker_probe
    var/list/assets = list("payload" = file("payload.txt"))

/proc/static_icon_probe()
    var/static/icon/flat_template = icon('probe.dmi', "")
    return flat_template
