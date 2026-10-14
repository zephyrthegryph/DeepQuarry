/datum/known_type
    var/amount = 0
var/global/value = /datum/known_type{amount=1}
/proc/probe()
    return value
