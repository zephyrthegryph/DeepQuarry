GLOBAL_VAR_INIT(spacevines_spawned, 0)

/datum/event/spacevine
	announceWhen	= 60

/datum/event/spacevine/start()
	spacevine_infestation()
	GLOB.spacevines_spawned = 1

/datum/event/spacevine/announce()
	GLOB.command_announcement.Announce("Hazardous plant infestation detected on \the [station_name()]. Station facilities may be overgrown.", "Hazardous Biomass")
