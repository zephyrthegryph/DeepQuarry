#if !defined(CITESTING)

/*********************/
/* MAP SELECTION     */
/* FOR LIVE SERVER   */
/*********************/

// Fast dev/test path: build with `-D USE_MAP_MINITEST` (see bin/dev.cmd) to boot
// the tiny virgo_minitest map instead of the full station. The station init is
// ~70s (Atoms/Atmos/Lighting over 3 decks); minitest is a few seconds, so use it
// for iterating on code that doesn't need the real station.
#ifndef USE_MAP_MINITEST
#define USE_MAP_SOUTHERN_CROSS
#endif

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
