// Types the virgo_minitest map data references that aren't compiled into the
// live tree (removed content, or defs that live in uncompiled submaps). Thin
// stubs so the fast dev/test map (built with -D USE_MAP_MINITEST, see bin/dev.cmd)
// compiles. Only included when minitest is the active map, so the live station
// build is untouched.

// Submap area used by the minitest layout — the real def lives in the
// (uncompiled) engine_submaps tree.
/area/submap/pa_room
	name = "PA Room"

// Minitest gateway + loot landmark referenced by the map data.
/obj/machinery/gateway/centeraway
	/// Whether the away gateway is calibrated (set in the minitest map data).
	var/calibrated = 0

/obj/effect/landmark/loot_spawn
