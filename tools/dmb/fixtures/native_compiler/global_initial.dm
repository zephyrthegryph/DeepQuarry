var/global/initial_probe = 4
/proc/initial_global()
    return initial(initial_probe)
/proc/initial_global_qualified()
    return initial(global.initial_probe)
/proc/saved_global()
    return issaved(initial_probe)
/proc/initial_local(value)
    var/local = 4
    local = 9
    value = 9
    return list(initial(local), initial(value))
/world/New()
    ..()
    initial_probe = 9
    world.log << "GLOBAL_INITIAL [initial_global()] [initial_global_qualified()] [saved_global()]"
    var/list/local_initials = initial_local(4)
    world.log << "LOCAL_INITIAL [local_initials.Join(",")]"
    del(world)
