/datum/thing
/proc/iterate_all()
    var/count = 0
    for(var/datum/thing/T)
        count++
    return count
