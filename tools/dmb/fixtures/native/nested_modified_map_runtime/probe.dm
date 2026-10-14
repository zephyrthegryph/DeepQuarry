// One-cell map contract; actual pinned BYOND reference must admit map syntax.
var/const/map_fixture_resource = 'contract-resource.txt'
/area/probe
/turf/probe
/obj/item
    var/amount = 1
/obj/parent
    var/child
    var/scalar = 0
/proc/body_marker()
    return 13
/world/New()
    ..()
    file2text(map_fixture_resource)
    var/obj/parent/parent = locate(/obj/parent) in locate(1,1,1)
    var/child_type = parent.child
    var/obj/item/item = new child_type()
    world.log << "DQ_NESTED parent_present [istype(parent, /obj/parent)]"
    world.log << "DQ_NESTED child_type [istype(item, /obj/item)]"
    world.log << "DQ_NESTED nested_amount [item.amount]"
    world.log << "DQ_NESTED leaf_scalar [parent.scalar]"
    world.log << "DQ_NESTED body_marker [body_marker()]"
    world.log << "DQ_NESTED finished"
    shutdown()
