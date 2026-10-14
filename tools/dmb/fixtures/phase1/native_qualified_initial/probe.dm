/datum/base
    var/value = 7
    var/var/obj/reference
/datum/child
    parent_type = /datum/base
    value = 9
/proc/check()
    return initial(/datum/base::value)
/proc/child_check()
    return initial(/datum/child::value)
