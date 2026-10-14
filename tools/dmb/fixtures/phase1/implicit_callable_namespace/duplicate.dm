/datum/base/verb/act()
    return 1
/datum/child
    parent_type = /datum/base
/datum/child/proc/act()
    return 2
/datum/both/verb/shared()
    return 3
/datum/both/proc/shared()
    return 4
