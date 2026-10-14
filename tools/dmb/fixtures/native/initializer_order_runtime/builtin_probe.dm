/world/proc/bootstrap()
    var/static/boot = order_mark("world_proc_first")
/var/global/root1 = order_mark("root1")
/obj/var/static/object_value = order_mark("obj")
/datum/var/static/datum_value = order_mark("datum")
/var/global/root2 = order_mark("root2")
/proc/root_static()
    var/static/value = order_mark("root_proc")
/proc/order_mark(label)
    world.log << "DQ_BUILTIN [label]"
    return 1
/world/New()
    ..()
    world.log << "DQ_BUILTIN finished"
    shutdown()
