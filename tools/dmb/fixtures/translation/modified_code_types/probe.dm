/datum/object_probe
    var/value = 2
    var/observed
    New()
        observed = value
/proc/probe()
    return new /datum/object_probe{value = 11}
/proc/again()
    return new /datum/object_probe{ value=11 }
