/datum/forwarding
    proc/single(value)
        return value
    proc/multiple(a, b)
        return a * 100 + b * 10 + args.len

/datum/forwarding/child
    single(value)
        value += 1
        return ..()
    multiple(a, b)
        a += 1
        b += 2
        args[3] = 9
        return ..()

/datum/forwarding/empty
    single(value)
        value += 1
        return ..(arglist(list()))

/world/New()
    ..()
    var/datum/forwarding/child/child = new
    var/datum/forwarding/empty/empty = new
    world.log << "PARENT_START"
    world.log << child.single(4)
    world.log << "PARENT_SINGLE"
    world.log << child.multiple(1, 2, 3)
    world.log << "PARENT_MULTIPLE"
    world.log << empty.single(4)
    world.log << "PARENT_EMPTY"
    world.log << "PARENT_FORWARD [child.single(4)] [child.multiple(1, 2, 3)] [empty.single(4)]"
    del(world)
