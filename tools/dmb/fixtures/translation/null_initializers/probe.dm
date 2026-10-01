/datum/holder/proc/managed()
    return list(1)
/proc/loop_default(datum/holder/O,list/L)
    O.managed()
    for(var/x in L)
        return x
    return 0
/proc/local_default(datum/holder/O)
    O.managed()
    var/x
    return x
/proc/local_authored(datum/holder/O)
    O.managed()
    var/x=null
    O.managed()
    return x
/proc/typed_loop_default(datum/holder/O,list/L)
    O.managed()
    for(var/datum/x in L)
        return x
    return 0
/proc/for_default(datum/holder/O)
    O.managed()
    for(var/x; x; x++)
        return x
    return 0
/proc/for_authored(datum/holder/O)
    O.managed()
    for(var/x=null; x; x++)
        return x
    return 0



