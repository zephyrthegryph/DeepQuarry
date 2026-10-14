/datum/receiver/verb/member_only()
    return 1
/proc/probe(datum/receiver/value)
    return value.member_only()
