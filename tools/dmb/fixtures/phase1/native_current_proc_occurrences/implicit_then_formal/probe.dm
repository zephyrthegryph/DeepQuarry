/datum/a/f()
    return __PROC__
/datum/a/proc/f()
    return list(__PROC__, ..())
/proc/probe(datum/a/a)
    return a.f()