var/init_order = ""
/proc/mark_order(label)
    init_order += label + "|"
    return label
var/global_z = mark_order("global_z")
/datum/init_marker
    New(label)
        ..()
        mark_order(label)
/datum/init_order/base
    var/static/static_z = mark_order("static_z")
    var/datum/init_marker/instance_z = new("instance_z")
    New()
        ..()
        mark_order("base_New")
    proc/local_static()
        var/static/local = mark_order("local_static")
        return local
/datum/init_order/child
    parent_type = /datum/init_order/base
    var/datum/init_marker/child_value = new("child_value")
    New()
        ..()
        mark_order("child_New")
var/global_a = mark_order("global_a")
/world/New()
    ..()
    phase0_emit("startup", init_order)
    var/datum/init_order/base/B = new
    phase0_emit("base_constructed", init_order)
    B.local_static()
    B.local_static()
    phase0_emit("local_static_twice", init_order)
    var/datum/init_order/child/C = new
    C.local_static()
    phase0_emit("child_constructed", init_order)
    phase0_finish()
