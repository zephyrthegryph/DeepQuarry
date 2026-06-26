#if !defined(CITESTING)

/*********************/
/* MAP SELECTION     */
/* FOR LIVE SERVER   */
/*********************/

// Southern Cross: re-ported from the CHOMPStation2 archive snapshot and adapted
// to the fork as a station-only map (the procedural surface/planet/overmap
// generation it originally relied on stays stubbed — those subsystems were
// removed during the hard fork). Deep Quarry remains available below.
#define USE_MAP_SOUTHERN_CROSS
//#define USE_MAP_DEEP_QUARRY

// Debug
//#define USE_MAP_MINITEST

/*********************/
/* End Map Selection */
/*********************/

#endif

#ifdef USE_MAP_MINITEST
#include "../virgo_minitest/virgo_minitest.dm"
#endif

// Deep Quarry boot wrapper now lives in the base maps/ tree.
#ifdef USE_MAP_DEEP_QUARRY
#include "../deep_quarry/deep_quarry.dm"
#endif

#ifdef USE_MAP_SOUTHERN_CROSS
#include "../southern_cross/southern_cross.dm"
#endif
