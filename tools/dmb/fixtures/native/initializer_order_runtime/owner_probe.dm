/proc/order_mark(label)
    world.log << "DQ_OWNER [label]"
    return 1

/datum/b
/datum/a

/datum/b/var/static/type_b1 = order_mark("type_b1")
/var/global/root1 = order_mark("root1")
/datum/a/proc/static_a()
    var/static/proc_a = order_mark("proc_a")
/datum/a/var/static/type_a1 = order_mark("type_a1")
/var/global/root2 = order_mark("root2")
/datum/b/proc/static_b()
    var/static/proc_b = order_mark("proc_b")
/datum/b/var/static/type_b2 = order_mark("type_b2")
/datum/a/var/static/type_a2 = order_mark("type_a2")

/world/New()
    ..()
    world.log << "DQ_OWNER finished"
    shutdown()
