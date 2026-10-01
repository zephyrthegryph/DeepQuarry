var/init_trace = ""
/datum/order_tracker
    var/label
    New(label)
        src.label = label
        mark_init(label)
/datum/order_base
    var/static/list/class_once = list(7)
    var/datum/order_tracker/values = new("base_instance")
    New()
        mark_init("new")
        world.log << "VALUES [values.label]"
    proc/local_once()
        var/static/list/value = list(8)
        value += 9
        return length(value)
/datum/order_base/child
    values = new /datum/order_tracker("child_instance")
var/datum/order_tracker/global_once = new("global")
/proc/mark_init(label)
    init_trace += label + "|"
    return label
/world/New()
    ..()
    world.log << "BOOT [init_trace]"
    var/datum/order_base/one = new
    world.log << "STATIC [one.local_once()] [one.local_once()] [length(one.class_once)]"
    var/datum/order_base/child/two = new
    world.log << "CHILDSTATIC [two.local_once()] [length(two.class_once)]"
    world.log << "FINAL [init_trace]"
    del(world)
