/proc/order_mark(label)
    world.log << "DQ_OWNER [label]"
    return 1

// References precede every declaration but this procedure is not called.
/proc/forward_refs()
    return global.root_second + /datum/later::later_first + /datum/empty::empty_late
/var/global/root_first = order_mark("root_first")
/datum/empty
/datum/later
/datum/later/var/static/later_first = order_mark("later_first")
/var/global/root_second = order_mark("root_second")
/datum/empty/var/static/empty_late = order_mark("empty_late")
/datum/later/proc/holder()
    var/static/local = order_mark("later_local")
/world/New()
    ..()
    world.log << "DQ_OWNER finished"
    shutdown()
