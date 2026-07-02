#if !defined(USING_MAP_DATUM)

	#include "virgo_minitest-1.dmm"
	#include "virgo_minitest-sector-2.dmm"
	#include "virgo_minitest-sector-3.dmm"

	#include "virgo_minitest_stubs.dm"
	#include "virgo_minitest_defines.dm"
	#include "virgo_minitest_shuttles.dm"
	#include "virgo_minitest_sectors.dm"

	#define USING_MAP_DATUM /datum/map/virgo_minitest

	// This is the CITESTING unit-test map (selected by _map_selection.dm under
	// -DCITESTING). It is intentionally NOT part of a live-server build — the live
	// map is Southern Cross. No commit-time #warn: this file is meant to be wired.

#elif !defined(MAP_OVERRIDE)

	#warn A map has already been included, ignoring Virgo_minitest

#endif
