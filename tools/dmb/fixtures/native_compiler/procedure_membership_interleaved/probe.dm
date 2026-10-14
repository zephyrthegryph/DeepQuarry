/datum/probe
/datum/probe/proc/alpha()
    return 1
/datum/probe/proc/beta()
    return 2
/datum/probe/alpha()
    return ..() + 3
/datum/probe/proc/gamma()
    return 4
/datum/probe/beta()
    return ..() + 5
