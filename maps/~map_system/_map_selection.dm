#if !defined(CITESTING)

/*********************/
/* MAP SELECTION     */
/* FOR LIVE SERVER   */
/*********************/

// Southern Cross: re-ported from the CHOMPStation2 archive snapshot and adapted
// to the fork as a station-only map (the procedural surface/planet/overmap
// generation it originally relied on stays stubbed — those subsystems were
// removed during the hard fork).
#define USE_MAP_SOUTHERN_CROSS

// Debug
//#define USE_MAP_MINITEST

/*********************/
/* End Map Selection */
/*********************/

#else

/*********************/
/* MAP FOR UNIT TEST */
/*********************/

// Under CITESTING the unit-test suite boots the tiny virgo_minitest map instead
// of the full 8-z Southern Cross station. A single small station z-level boots in
// seconds vs ~10 min, and the atmos tests (which scan the live main map for floor
// pairs, since the unit_tests.dmm sealed-room template isn't loaded — see
// unit_test.dm New()) get a clean purpose-built station instead of pathological
// Southern Cross turfs (airlock tiles, closets, unsimulated planetary floors).
#define USE_MAP_MINITEST

/*********************/
/* End Map Selection */
/*********************/

#endif

#ifdef USE_MAP_MINITEST
#include "../virgo_minitest/virgo_minitest.dm"
#endif

#ifdef USE_MAP_SOUTHERN_CROSS
#include "../southern_cross/southern_cross.dm"
#endif
