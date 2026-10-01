/var/const/A=null
/datum/base
    var/const/C=null
    proc/read_c()
        return C
/datum/child
    parent_type=/datum/base
/proc/global_read()
    return A
/proc/local_read()
    var/const/B=null
    return B
/proc/local_other()
    var/const/B=null
    return B

/proc/owner()
    return new /datum/base
/proc/typed(datum/base/O)
    return O.C
/proc/computed()
    return owner().C
/proc/safe(datum/base/O)
    return O?.C
/proc/computed_safe()
    return owner()?.C
/proc/new_computed()
    return (new /datum/base()).C
/proc/new_safe()
    return (new /datum/base())?.C
/datum/other
    var/const/C=null
