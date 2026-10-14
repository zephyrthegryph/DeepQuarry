/proc/probe()
    var/list/value = list(7)
    for(var/datum/value = new; value; value = null)
        break
    return value.Copy()
