// The world entity: what world-wide events are emitted on.

/// The entity world-wide events are emitted on (was the DCS global signal target,
/// SEND_GLOBAL_SIGNAL). Observe it with observe(OM_WORLD, /datum/notice/x, listener, ...) or an action of it with observe(OM_WORLD, /datum/act/x, ...).
/datum/om_world
GLOBAL_DATUM_INIT(om_world, /datum/om_world, new)
