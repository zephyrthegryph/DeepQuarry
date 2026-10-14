/datum/base/verb/act()
    return 1
/datum/child
    parent_type = /datum/base
/datum/child/act()
    return 2
/datum/same/act()
    return 4
/datum/same/verb/act()
    return 5
