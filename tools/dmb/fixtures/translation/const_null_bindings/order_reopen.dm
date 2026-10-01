/datum/other
/datum/base
    var/const/C=null
/datum/other
    var/const/C=null
/proc/computed()
    return owner().C
/proc/owner()
    return new /datum/base
