// Independent boot receiver and ordered global initializer contract.
var/global/datum/boot_early/early_receiver = new
var/global/list/cache_store = list(); var/global/cache_hash = 0; var/global/datum/boot_cache/cache_receiver = new
var/global/datum/boot_config/config_receiver = new
var/global/datum/boot_config/null_receiver

/datum/boot_early/New()
    ..()
    world.log << "DQ_BOOT early_cache_null [isnull(global.cache_receiver)]"
    world.log << "DQ_BOOT early_cache_typed [istype(global.cache_receiver, /datum/boot_cache)]"
    if(istype(global.cache_receiver, /datum/boot_cache))
        world.log << "DQ_BOOT early_cache_direct [global.cache_receiver.guarded()]"

/datum/boot_cache/proc/guarded()
    return 42

/datum/boot_config
    var/loaded = 0

/proc/boot_forbid()
    return 0

/world/Profile(command, type, format)
    if((command & 1) || !global.null_receiver?.loaded || !boot_forbid())
        return 17
    return 18

/world/New()
    ..()
    world.log << "DQ_BOOT null_safe [global.null_receiver?.loaded]"
    world.log << "DQ_BOOT null_not [!global.null_receiver?.loaded]"
    world.log << "DQ_BOOT configured_loaded [global.config_receiver?.loaded]"
    world.log << "DQ_BOOT configured_not [!global.config_receiver?.loaded]"
    world.log << "DQ_BOOT or_null [(0 & 1) || !global.null_receiver?.loaded || !boot_forbid()]"
    world.log << "DQ_BOOT or_short [(1 & 1) || !global.null_receiver?.loaded || !boot_forbid()]"
    world.log << "DQ_BOOT callback [Profile(2)]"
    world.log << "DQ_BOOT callback_short [Profile(1)]"
    world.log << "DQ_BOOT cache_list [islist(global.cache_store)]"
    world.log << "DQ_BOOT cache_hash [global.cache_hash]"
    world.log << "DQ_BOOT cache_safe [global.cache_receiver?.guarded()]"
    world.log << "DQ_BOOT cache_direct [global.cache_receiver.guarded()]"
    world.log << "DQ_BOOT finished"
    shutdown()
