/datum/sre
    var/value
    var/datum/sre/child
/proc/sre_nested(list/L, key, datum/sre/O)
    L[key] = O?.child?.value
    return L
/proc/sre_index(list/L, key, datum/sre/O)
    L[key] = O?.value["k"]
    return L
