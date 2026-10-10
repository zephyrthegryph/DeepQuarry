/datum/other/proc/known()
    return 1
/proc/probe(datum/other/value)
    return value?.known()
