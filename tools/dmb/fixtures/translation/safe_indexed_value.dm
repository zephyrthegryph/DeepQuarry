/datum/siv
    var/value = 4
    proc/read_value()
        return value
/proc/siv_owner(datum/siv/O)
    return O
/proc/siv_global(list/L, key, datum/siv/O)
    L[key] = siv_owner(O)?.value
    return L
/proc/siv_method(list/L, key, datum/siv/O)
    L[key] = O?.read_value()
    return L
