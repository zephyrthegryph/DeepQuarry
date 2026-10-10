/datum/order_owner/proc/zebra()
    return 1
/datum/order_owner/proc/alpha()
    return 2
/datum/order_owner/proc/middle()
    return 3
/datum/order_owner/alpha()
    return ..() + 2
/datum/order_owner/child/proc/child_last()
    return 5
/datum/order_owner/child/proc/child_first()
    return 6
/world/New()
    ..()
    for(var/item in typesof(/datum/order_owner/proc))
        world.log << "DQ_ENUM base [item]"
    for(var/child_item in typesof(/datum/order_owner/child/proc))
        world.log << "DQ_ENUM child [child_item]"
    world.log << "DQ_ENUM finished"
    shutdown()
