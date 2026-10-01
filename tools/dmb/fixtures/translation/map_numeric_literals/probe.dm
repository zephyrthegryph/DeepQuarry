/obj/map_numeric
    var/value = 0
/world/New()
    ..()
    for(var/obj/map_numeric/O in world)
        world.log << "MAP_NUMBER value=[O.value] pixels=[O.pixel_x],[O.pixel_y]"
