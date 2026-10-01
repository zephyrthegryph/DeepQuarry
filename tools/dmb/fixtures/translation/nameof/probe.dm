/datum/x/proc/foo()
    return 1
/datum/x/proc/get()
    return nameof(.proc/foo)
/datum/x/proc/get2()
    return nameof(/datum/x/proc/foo)
