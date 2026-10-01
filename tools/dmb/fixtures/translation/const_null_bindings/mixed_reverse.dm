/datum/other
    var/C=7
/datum/base
    var/const/C=null
/proc/computed()
    return owner().C
/proc/owner()
    return new /datum/base
