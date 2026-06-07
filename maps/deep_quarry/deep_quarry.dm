// Boot wrapper for the Deep Quarry station map.
// Selected via USE_MAP_DEEP_QUARRY in modular_chomp/maps/~map_system/_map_selection.dm.

#if !defined(USING_MAP_DATUM)

	#include "deep_quarry_defines.dm"
	#include "deep_quarry_areas.dm"

	#ifndef AWAY_MISSION_TEST
		#include "deep_quarry-1.dmm"  // z1: stone landscape with central room
	#endif

	#define USING_MAP_DATUM /datum/map/deep_quarry

#elif !defined(MAP_OVERRIDE)

	#warn A map has already been included, ignoring Deep Quarry

#endif
