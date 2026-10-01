/datum/base/child
/datum/other
    var/const/C=null
/datum/base
    var/const/C=null
/proc/owner()
    return new /datum/base/child
/proc/unknown()
    return owner().C
/proc/typed(datum/base/child/O)
    return O.C
/proc/safe(datum/base/child/O)
    return O?.C
/proc/colon(datum/base/child/O)
    return O:C
/proc/safe_colon(datum/base/child/O)
    return O?:C
