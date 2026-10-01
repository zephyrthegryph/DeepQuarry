/world
    map_format = TOPDOWN_MAP

/turf/fixture_floor
    name = "fixture floor"

/area/fixture_room
    name = "fixture room"

/obj/fixture_marker
    var/amount = 9

/world/New()
    ..()
    var/turf/T = locate(1, 1, 1)
    var/obj/fixture_marker/M = locate(/obj/fixture_marker) in T
    world.log << "MAPS [world.maxx] [world.maxy] [world.maxz] [T.name] [M.amount]"
