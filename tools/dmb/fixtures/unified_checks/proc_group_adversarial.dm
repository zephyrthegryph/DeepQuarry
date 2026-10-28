/datum/z/proc/probe(a, b)
    return !a & b
/datum/a
    parent_type = /datum/z
/datum/a/probe(a, b)
    return !a | b
/datum/a/child
    parent_type = /datum
/datum/a/child/proc/probe(a, b)
    return !a ^ b

/datum/test/proc/z()
/datum/test/proc/a(a, b)
    return !a & b
/datum/test/z(a, b)
    return !a | b

