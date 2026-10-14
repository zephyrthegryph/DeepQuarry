/datum/present_type
    var/amount = 0
var/global/value = /datum/present_type{amount=1}
/proc/probe()
    return value
