/datum/name_shadow
    var/icon = 1
/proc/probe()
    var/datum/name_shadow/local
    var/static/name = nameof(local.icon)
    return name
