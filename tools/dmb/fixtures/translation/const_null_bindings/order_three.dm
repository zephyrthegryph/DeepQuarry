/datum/first
    var/const/C=null
/datum/second
    var/const/C=null
/datum/third
    var/const/C=null
/proc/computed()
    return owner().C
/proc/pure(datum/first/O)
    return O:C
/proc/safe(datum/first/O)
    return O?:C
/proc/owner()
    return new /datum/first
/proc/typed(datum/first/O)
    return O.C
/proc/typed_safe(datum/first/O)
    return O?.C
