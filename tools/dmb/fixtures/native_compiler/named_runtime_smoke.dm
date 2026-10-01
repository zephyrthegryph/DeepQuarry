/datum/named_target
    var/base = 0
    var/abstract_type = /datum/named_target

/datum/named_target/New(base = 0, extra = 0)
    ..()
    src.base = base + extra

/datum/named_target/proc/sum(a, b)
    return base + a + b

/datum/named_target/proc/forward()
    return sum(b = 3, a = 2)

/proc/named_global(a, b)
    return a * 10 + b

/proc/named_runtime_check()
    var/datum/named_target/target = new /datum/named_target(extra = 4, base = 1)
    if(target.base != 5)
        return -1
    if(target.sum(b = 2, a = 1) != 8)
        return -2
    if(target.forward() != 10)
        return -3
    if(named_global(b = 2, a = 1) != 12)
        return -4
    var/datum/named_target/path = /datum/named_target
    if(path::abstract_type != /datum/named_target)
        return -5
    return 29

/world/New()
    ..()
    world.log << "RUST_NAMED_SMOKE [named_runtime_check()]"
    del(world)
