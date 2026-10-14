/datum/base/proc/f()
    return 1
/datum/child
    parent_type = /datum/base
/datum/child/f()
    return ..()
/datum/zero/f()
    return ..()
/datum/zero/proc/f()
    return ..()
/datum/two/f()
    return 1
/datum/two/f()
    return 2
/datum/two/proc/f()
    return 3
/proc/global_parentless()
    return ..()
