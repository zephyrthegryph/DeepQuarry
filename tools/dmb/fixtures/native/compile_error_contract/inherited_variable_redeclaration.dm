/datum/base
    var/value = 1
/datum/child
    parent_type = /datum/base
    var/value = 2
/proc/probe()
    var/datum/child/item = new
    return item.value
