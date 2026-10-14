var/phase0_creation = ""
/turf/phase0_floor
    New()
        phase0_creation += "turf([x],[y],[z])|"
        ..()
/area/phase0_area
    New()
        phase0_creation += "area|"
        ..()
/obj/phase0_placed
    var/label = "base"
    New()
        phase0_creation += "[label]([x],[y],[z])|"
        ..()
/obj/phase0_placed/z_item
    label = "z_item"
/obj/phase0_placed/a_item
    label = "a_item"
/world/New()
    ..()
    phase0_emit("creation_before_world_new", phase0_creation)
    var/list/placements = list()
    for(var/obj/phase0_placed/O in world)
        placements += "[O.type]@[O.x],[O.y],[O.z]"
    phase0_emit("placed_world_iteration", placements)
    phase0_finish()
