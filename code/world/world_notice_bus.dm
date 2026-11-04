// The world entity: what world-wide events are emitted on.

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/world_notice_bus)
/// The entity world-wide events are emitted on (was the DCS global signal target,
/// SEND_GLOBAL_SIGNAL). Observe it with observe(WORLD_NOTICE_BUS, /datum/notice/x, listener, ...) or an action of it with observe(WORLD_NOTICE_BUS, /datum/act/x, ...).
/datum/world_notice_bus
GLOBAL_DATUM_INIT(world_notice_bus, /datum/world_notice_bus, new)
