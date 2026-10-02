// System accessors: the var must exist on the system.
/datum/world_service/lamps
	var/on = FALSE
	var/bright = 3

/datum/system/pumps
	var/running = FALSE

SYSTEM_ACCESSOR(lamps, lamps_on, nameof(on))
SYSTEM_ACCESSOR(lamps, lamps_dim, nameof(dim))
SYSTEM_ACCESSOR(pumps, pumps_running, nameof(running))
SYSTEM_ACCESSOR(ghost, ghost_value, nameof(value))
