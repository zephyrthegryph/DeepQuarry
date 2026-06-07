#if !defined(CITESTING)

/*********************/
/* MAP SELECTION     */
/* FOR LIVE SERVER   */
/*********************/

// DQEdit Start — booting into Deep Quarry instead of Southern Cross for the new fork.
// #define USE_MAP_SOUTHERN_CROSS
#define USE_MAP_DEEP_QUARRY
// DQEdit End
// #define USE_MAP_CETUS
// #define USE_MAP_SOLUNA_NEXUS
// #define USE_MAP_RELIC_BASE

// Debug
//#define USE_MAP_MINITEST

/*********************/
/* End Map Selection */
/*********************/

#endif

// Southern Cross
#ifdef USE_MAP_SOUTHERN_CROSS
#include "../southern_cross/southern_cross.dm"
#endif

// Soluna Nexus
#ifdef USE_MAP_SOLUNA_NEXUS
#include "../soluna_nexus/soluna_nexus.dm"
#endif

// Cetus
#ifdef USE_MAP_CETUS
#include "../cetus/cetus.dm"
#endif

// Relic Base
#ifdef USE_MAP_RELIC_BASE
#include "../relic_base/relicbase.dm"
#endif

#ifdef USE_MAP_MINITEST
#include "../virgo_minitest/virgo_minitest.dm"
#endif

// DQAdd Start — Deep Quarry boot wrapper now lives in the base maps/ tree.
#ifdef USE_MAP_DEEP_QUARRY
#include "../../../maps/deep_quarry/deep_quarry.dm"
#endif
// DQAdd End
