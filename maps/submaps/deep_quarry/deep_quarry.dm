// deep quarry submap registration for the entrance level.
// This causes the PoI maps to get compiled-checked during MAP_TEST CI.
#ifdef MAP_TEST
#include "deep_quarry_entrance.dmm"
#endif

/datum/map_template/surface/deep_quarry
	name = "Deep Quarry"
	desc = "An old stone quarry that goes deeper than anyone has bothered to map."

/datum/map_template/surface/deep_quarry/entrance
	name = "Deep Quarry - Entrance"
	desc = "A small stone room at the head of a long-abandoned quarry."
	mappath = "maps/submaps/deep_quarry/deep_quarry_entrance.dmm"
	cost = 30
