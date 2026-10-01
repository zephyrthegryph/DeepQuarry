/datum/order/proc/check(original_arg)
    return 1
/datum/order/check(override_arg, extra_arg)
    return 2
/datum/order/proc/other()
    return 3
/world/proc/check(original_world_arg)
    return 4
/world/check(override_world_arg, extra_world_arg)
    return 5
/world/proc/other()
    return 6
/var/list/force516=alist()
/datum/order/child/check()
    return 7