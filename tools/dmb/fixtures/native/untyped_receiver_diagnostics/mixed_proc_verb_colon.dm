/datum/other/verb/verb_known()
    return 1
/datum/third/proc/verb_known()
    return 2
/proc/probe(value)
    return value:verb_known()
