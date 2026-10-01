/datum/proc/foo(value)
    return value
/proc/probe(datum/D)
    return D?.foo(value=3)
