/datum/receiver/proc/read_value()
    return 7
/proc/probe()
    for(var/datum/receiver/value = new /datum/receiver; value; value = null)
        return value.read_value()
    return 0
