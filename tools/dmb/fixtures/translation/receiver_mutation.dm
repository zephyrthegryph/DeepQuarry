/datum/rm_owner/proc/method(value)
    return value
/proc/rm_direct(var/datum/rm_owner/a,var/datum/rm_owner/b)
    return a.method((a = b))
/proc/rm_identity(var/datum/rm_owner/a)
    return a
/proc/rm_computed(var/datum/rm_owner/a,var/datum/rm_owner/b)
    return rm_identity(a).method((a = b))