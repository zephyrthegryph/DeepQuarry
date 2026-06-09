// Z-level numbering. Deep Quarry currently has only one compiled-in z-level.
#define Z_LEVEL_DQ_MAIN 1

/datum/map/deep_quarry
	name = "Deep Quarry"
	full_name = "Deep Quarry"
	path = "deep_quarry"

	zlevel_datum_type = /datum/map_z_level/deep_quarry

	station_name  = "Deep Quarry"
	station_short = "Quarry"
	facility_type = "outpost"
	dock_name     = "Surface Anchor"
	boss_name     = "Surface Command"
	boss_short    = "Surface"
	company_name  = "Deep Quarry Co."
	company_short = "DQ"
	starsys_name  = "Unknown"

	use_overmap = FALSE

	allowed_spawns = list("Arrivals Shuttle")

	// Without a real arrivals shuttle we just dump the dead at the entrance too.
	spawnpoint_died = /datum/spawnpoint/arrivals
	spawnpoint_left = /datum/spawnpoint/arrivals
	spawnpoint_stayed = /datum/spawnpoint/arrivals

	lobby_screens = list('html/lobby/mockingjay00.webp')

/datum/map_z_level/deep_quarry/main
	z = Z_LEVEL_DQ_MAIN
	name = "Deep Quarry"
	flags = MAP_LEVEL_STATION|MAP_LEVEL_CONTACT|MAP_LEVEL_PLAYER|MAP_LEVEL_CONSOLES|MAP_LEVEL_VORESPAWN
	base_turf = /turf/simulated/mineral/floor/cave
