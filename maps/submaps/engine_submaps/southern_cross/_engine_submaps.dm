#ifdef MAP_TEST
#include "engine_sme.dmm"
#include "engine_tesla.dmm"
#endif

/datum/map_template/engine
	name = "Engine Content"
	desc = "A selectable station engine installation."
	allow_duplicates = FALSE

/datum/map_template/engine/supermatter
	name = "Supermatter Engine"
	desc = "Thermoelectric supermatter engine."
	mappath = "maps/submaps/engine_submaps/southern_cross/engine_sme.dmm"

/datum/map_template/engine/tesla
	name = "Edison's Bane"
	desc = "Tesla engine."
	mappath = "maps/submaps/engine_submaps/southern_cross/engine_tesla.dmm"
