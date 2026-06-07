#if !defined(CITESTING)

/*********************/
/* MAP SELECTION     */
/* FOR LIVE SERVER   */
/*********************/

// DQEdit Start — the fork boots Deep Quarry. The legacy CHOMP station maps
// (Southern Cross, Cetus, Soluna Nexus, Relic Base) were removed during the
// hard-fork merge: they referenced surface map_template types that no longer
// exist in-repo and had been dead since the fork switched to Deep Quarry.
#define USE_MAP_DEEP_QUARRY
// DQEdit End

// Debug
//#define USE_MAP_MINITEST

/*********************/
/* End Map Selection */
/*********************/

#endif

#ifdef USE_MAP_MINITEST
#include "../virgo_minitest/virgo_minitest.dm"
#endif

// DQAdd Start — Deep Quarry boot wrapper now lives in the base maps/ tree.
#ifdef USE_MAP_DEEP_QUARRY
#include "../deep_quarry/deep_quarry.dm"
#endif
// DQAdd End
