
#define Z_LEVEL_MAIN_VIRGO_TESTING					1

/datum/map/virgo_minitest
	name = "Virgo_minitest"
	full_name = "NSS Ade-testing"
	path = "virgo_minitest"

	lobby_screens = list('html/lobby/chompstation_eggman.gif')

	id_hud_icons = 'icons/mob/hud_jobs_vr.dmi'

	accessible_z_levels = list("1" = 100)
	base_turf_by_z = list("1" = /turf/space)

	use_overmap = TRUE

	zlevel_datum_type = /datum/map_z_level/minitest

	// Minimal CI harness, not a complete station — skip the whole-station APC/vent/
	// scrubber-coverage and wiring validity tests (they run against the live map).
	skip_map_validity_tests = TRUE
	skipped_tests = list(
		/datum/unit_test/dq_arrivals_shuttle_preserves_air,
		/datum/unit_test/dq_escape_shuttle_preserves_air,
		/datum/unit_test/dq_live_carrier_independently_orbits_sif,
		/datum/unit_test/dq_live_flight_payload_preserves_carrier_hierarchy,
		/datum/unit_test/dq_station_flight_never_substitutes_carrier_port,
		/datum/unit_test/dq_southern_cross_berth_fits_every_expedition_craft,
	)

	station_name  = "NSS Ade-testing"
	station_short = "VORE-testing"
	dock_name     = "Virgo-test CC"
	dock_type     = "surface"
	boss_name     = "Central Command-testing"
	boss_short    = "CentCom-testing"
	company_name  = "NanoTrasen-testing"
	company_short = "NT-testing"
	starsys_name  = "Virgo-Erigone-testing"

	shuttle_docked_message = "Test Shuttle Docked"
	shuttle_leaving_dock = "Test Shuttle Leaving"
	shuttle_called_message = "Test Shuttle Coming"
	shuttle_recall_message = "Test Shuttle Cancelled"
	shuttle_name = "NAS |Hawking|"
	emergency_shuttle_docked_message = "Test E-Shuttle Docked"
	emergency_shuttle_leaving_dock = "Test E-Shuttle Left"
	emergency_shuttle_called_message = "Test E-Shuttle Coming"
	emergency_shuttle_recall_message = "Test E-Shuttle Cancelled"

	station_networks = list(
							NETWORK_CARGO,
							NETWORK_CIVILIAN,
							NETWORK_COMMAND,
							NETWORK_ENGINE,
							NETWORK_ENGINEERING,
							NETWORK_ENGINEERING_OUTPOST,
							NETWORK_DEFAULT,
							NETWORK_MEDICAL,
							NETWORK_MINE,
							NETWORK_NORTHERN_STAR,
							NETWORK_RESEARCH,
							NETWORK_RESEARCH_OUTPOST,
							NETWORK_ROBOTS,
							NETWORK_PRISON,
							NETWORK_SECURITY,
							NETWORK_INTERROGATION
							)

	allowed_spawns = list("Arrivals Shuttle","Gateway","Cryogenic Storage","Cyborg Storage")

/datum/map_z_level/minitest/station
	z = Z_LEVEL_MAIN_VIRGO_TESTING
	name = "Station Level"
	flags = MAP_LEVEL_STATION|MAP_LEVEL_CONTACT|MAP_LEVEL_PLAYER|MAP_LEVEL_CONSOLES|MAP_LEVEL_XENOARCH_EXEMPT
	holomap_legend_x = 220
	holomap_legend_y = 160

/datum/map/virgo_minitest/perform_map_generation()
/*
	new /datum/random_map/automata/cave_system(null, 1, 1, Z_LEVEL_MAIN_VIRGO_TESTING, world.maxx, world.maxy)
	new /datum/random_map/noise/ore(null, 1, 1, Z_LEVEL_MAIN_VIRGO_TESTING, 64, 64)
*/
	return 1
