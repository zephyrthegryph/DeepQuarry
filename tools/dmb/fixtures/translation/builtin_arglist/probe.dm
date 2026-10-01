/proc/picklist(list/L)
    return pick(arglist(L))
/proc/genlist(list/L)
    return generator(arglist(L))
/proc/ctorlist(list/L)
    var/datum/D = new(arglist(L))
    return D
