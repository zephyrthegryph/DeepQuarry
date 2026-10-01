/datum/thing
    proc/place()
        return 1
/proc/construct(var/datum/thing/t, var/a)
    return new t.type(t.place(), a)
