/world
    name = "OpenDream DMB smoke"
/world/New()
    ..()
    world.log << "SMOKE READY"
    world.log << add(2, 3)
/proc/add(a, b)
    return a + b
/obj/item
    var/value = 5
/obj/item/proc/get_value()
    return value
