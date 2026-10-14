/proc/order_mark(label)
    world.log << "DQ_OWNER [label]"
    return 1

// Empty custom owners precede root; their writes appear after root's first write.
/datum/empty
/datum/later
/var/global/root_first = order_mark("root_first")
/datum/later/var/static/later_first = order_mark("later_first")
/datum/empty/var/static/empty_late = order_mark("empty_late")
/var/global/root_second = order_mark("root_second")
/datum/later/proc/holder()
    var/static/local = order_mark("later_local")

/world/New()
    ..()
    world.log << "DQ_OWNER finished"
    shutdown()
