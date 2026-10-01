/datum/static_context/proc/current()
    var/static/p = __PROC__
    var/static/t = __TYPE__
    return list(p, t)
