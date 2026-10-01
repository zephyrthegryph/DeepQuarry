/datum/static_inherited_base
    var/value = 5
/datum/static_inherited_base/child
/proc/probe_static_inherited()
    return /datum/static_inherited_base/child::value
