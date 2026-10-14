// The first included declaration mirrors the generated Genesis bootstrap.
/world/proc/_()
    var/static/bootstrap = world.Genesis()

/world/proc/Genesis()
    world.log << "DQ_ORDER genesis_cache [istype(global.cache_receiver, /datum/order_cache)]"
    world.log << "DQ_ORDER genesis_config [istype(global.config_receiver, /datum/order_config)]"
    return 1

var/global/datum/order_early/early_receiver = new

/datum/order_early/New()
    ..()
    world.log << "DQ_ORDER global_early"

/proc/middle_static()
    var/static/middle = order_mark("static_middle")
    return middle

var/global/list/cache_store = list(); var/global/cache_hash = 0; var/global/datum/order_cache/cache_receiver = new

/datum/order_cache/New()
    ..()
    world.log << "DQ_ORDER global_cache"

var/global/datum/order_config/config_receiver = new

/datum/order_config/New()
    ..()
    world.log << "DQ_ORDER global_config"

/proc/last_static()
    var/static/last = order_mark("static_last")
    return last

/proc/order_mark(label)
    world.log << "DQ_ORDER [label]"
    return 1

/world/New()
    ..()
    world.log << "DQ_ORDER world_cache [istype(global.cache_receiver, /datum/order_cache)]"
    world.log << "DQ_ORDER world_config [istype(global.config_receiver, /datum/order_config)]"
    world.log << "DQ_ORDER finished"
    shutdown()
