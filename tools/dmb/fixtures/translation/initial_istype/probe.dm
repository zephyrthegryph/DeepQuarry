/datum/x
    var/value = 7
/proc/test(datum/x/x)
    return initial(x.value)
/proc/istype_test(x)
    return istype(x, /datum/x)
/proc/istype_implicit(datum/x/x)
    return istype(x)
