/datum/first
/datum/second

/datum/first/proc/alpha(a, b)
    return !a & b
/datum/second/proc/beta(a, b)
    return !a ^ b
/datum/first/alpha(a, b)
    return !a | b
/datum/first/proc/gamma(a, b)
    return !a & b
/datum/first/gamma(a, b)
    return !a ^ b
