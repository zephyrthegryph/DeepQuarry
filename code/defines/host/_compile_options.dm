#define BACKGROUND_ENABLED 0    // The default value for all uses of set background. Set background can cause gradual lag and is recommended you only turn this on if necessary.
								// 1 will enable set background. 0 will disable set background.

#define PRELOAD_RSC 1			/*set to:
								0 to allow using external resources or on-demand behaviour;
								1 to use the default behaviour (preload compiled in recourses, not player uploaded ones);
								2 for preloading absolutely everything;
								*/

// ZAS Compile Options
//#define FIREDBG		// Uncomment to turn on ZAS debugging related to fire stuff.
//#define ZASDBG	 	// Uncomment to turn on super detailed ZAS debugging that probably won't even compile.
#define MULTIZAS		// Uncomment to turn on Multi-Z ZAS Support!

// Movement Compile Options
//#define CARDINAL_INPUT_ONLY // Uncomment to disable diagonal player movement (restore previous cardinal-moves-only behavior)

// CI will override these as appropriate
// #define MAP_TEST 0
// #define UNIT_TESTS 1

#if defined(CIBUILDING) && !defined(OPENDREAM)
#define UNIT_TESTS
#endif

// Comment/Uncomment this to turn off/on shuttle code debugging logs
#define DEBUG_SHUTTLES

// If we are doing the map test build, do not include the main maps, only the submaps.
#ifdef MAP_TEST
	#define USING_MAP_DATUM /datum/map
	#define MAP_OVERRIDE 1
#endif

// Reference finder (harddel hunting). OFF in production and local server
// builds: with GC_FAILURE_HARD_LOOKUP every object that survives its first GC
// retry triggers a full datum-graph walk with no tick checks, freezing the
// world for minutes (and Windows then kills the BYOND client).
// Opt in explicitly:
//   tools/build/build.sh -DREFERENCE_TRACKING        tracking + admin "Find References", per-object hints
//   tools/build/build.sh -DGC_FAILURE_HARD_LOOKUP    also auto-search every GC failure (freezes the world)
// Unit-test builds (UNIT_TESTS) keep both on: find_reference_sanity and the
// GC tests rely on them. See doc/testing.md "Reference tracking".
#if defined(UNIT_TESTS) && !defined(GC_FAILURE_HARD_LOOKUP)
#define GC_FAILURE_HARD_LOOKUP
#endif
#if defined(GC_FAILURE_HARD_LOOKUP) && !defined(REFERENCE_TRACKING)
#define REFERENCE_TRACKING
#endif
#ifdef REFERENCE_TRACKING

// #define FIND_REF_NO_CHECK_TICK // new ref tracking
///Should we be logging our findings or not
#define REFERENCE_TRACKING_LOG

///Used for doing dry runs of the reference finder, to test for feature completeness
#define REFERENCE_TRACKING_DEBUG

/// Hard lookup searches without tick checks (the old dev-server policy).
#if defined(GC_FAILURE_HARD_LOOKUP) && !defined(FIND_REF_NO_CHECK_TICK)
#define FIND_REF_NO_CHECK_TICK
#endif

// Test builds keep BYOND's infinite-loop detection: with it off, a runaway
// loop anywhere (not just in the reference finder) hangs the suite silently
// until the watchdog kills it, with no stack to say where.
#if defined(FIND_REF_NO_CHECK_TICK) && !defined(UNIT_TESTS)
/world
	loop_checks = FALSE
#endif

#endif //ifdef REFERENCE_TRACKING

// Standard flags to use for browser-options
#define DEFAULT_CLIENT_BROWSER_OPTIONS "find"
