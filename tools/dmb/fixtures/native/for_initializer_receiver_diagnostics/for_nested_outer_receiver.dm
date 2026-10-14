/proc/probe()
    var/list/outer = list(7)
    for(var/datum/value = new; value; value = null)
        for(var/list/inner = list(11); inner; inner = null)
            break
        break
    return outer.Copy()[1]
