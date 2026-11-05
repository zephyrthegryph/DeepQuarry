// Placement paths that edited turfs one by one while loading now plan the final turfs as data and place them as one load (place_turfs):
// the rogue-miner asteroid, a deployed shelter's roof and a clearing shuttle landmark. Proved by the load count, the ChangeTurf count and the
// frames, and by what ends up on the ground.

/// A fresh expedition z-level and the number of loads and ChangeTurf calls so far, for the test to compare.
/proc/dq_firstload_paths_z()
	var/datum/map_template/expedition_site/template = new
	return template.load_new_z()

/// A 3x3 asteroid with a wall rim and a floor core is placed as one load; the ore pass sees the placed vacuum rock.
/datum/unit_test/dq_firstload_asteroid_one_load

/datum/unit_test/dq_firstload_asteroid_one_load/Run()
	test_driver_begin()
	var/made_controller = FALSE
	if(!GLOB.rm_controller)
		GLOB.rm_controller = new /datum/controller/rogue
		made_controller = TRUE
	var/z = dq_firstload_paths_z()
	var/turf/center = locate(50, 50, z)
	var/datum/rogue/zonemaster/ZM = new(get_area(center))
	var/obj/asteroid_spawner/SP = new(center)
	var/datum/rogue/asteroid/predef/cargo/A = new
	var/loads_before = GLOB.place_turfs_load_count
	var/changes_before = GLOB.turf_change_calls
	SSatoms.batch_trace = list()
	ZM.place_asteroid(A, SP)
	var/list/frames = SSatoms.batch_trace
	SSatoms.batch_trace = null
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_before, 1, "the asteroid was placed as one load")
	TEST_ASSERT_EQUAL(length(frames), 1, "the asteroid initialized in one frame")
	var/cells = 0
	for(var/list/column in A.map)
		for(var/list/cell in column)
			if(length(cell))
				cells++
	TEST_ASSERT(cells > 0, "the asteroid plans cells")
	TEST_ASSERT(GLOB.turf_change_calls - changes_before <= cells, "at most one ChangeTurf per planned cell")
	for(var/x in 1 to A.width)
		for(var/y in 1 to A.width)
			var/list/cell = A.map[x][y]
			for(var/entry in cell)
				if(ispath(entry, /turf))
					var/turf/T = locate(SP.x - A.width / 2 + x, SP.y - A.width / 2 + y, z)
					TEST_ASSERT_EQUAL(T.type, entry, "the cell at [T.x],[T.y] is its planned turf")
					TEST_ASSERT(T.flags & ATOM_INITIALIZED, "the cell at [T.x],[T.y] is initialized")
	if(made_controller)
		GLOB.rm_controller = null
	test_driver_end()

/// A shelter roof covers open space with one load, and only open space.
/datum/unit_test/dq_firstload_shelter_roof_one_load

/datum/unit_test/dq_firstload_shelter_roof_one_load/Run()
	test_driver_begin()
	var/z = dq_firstload_paths_z()
	// Open space needs a level below it: link this level to the one under it for the test.
	var/list/levels_before = GLOB.z_levels.Copy()
	while(length(GLOB.z_levels) < z - 1)
		GLOB.z_levels += FALSE
	GLOB.z_levels[z - 1] = TRUE
	var/list/open_types = list()
	for(var/x in 60 to 62)
		for(var/y in 60 to 62)
			open_types[locate(x, y, z)] = /turf/simulated/open
	place_turfs(open_types, label = "roof test setup")
	var/turf/solid = locate(61, 61, z)
	solid.ChangeTurf(/turf/simulated/wall, tell_universe = FALSE)
	var/datum/map_template/shelter/template = new
	var/loads_before = GLOB.place_turfs_load_count
	template.add_roof(locate(61, 61, z))
	var/roofed = 0
	for(var/turf/T as anything in open_types)
		if(istype(T, /turf/simulated/shuttle/floor/voidcraft))
			roofed++
	TEST_ASSERT(roofed > 0, "open turfs were roofed")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_before, 1, "the roof was placed as one load")
	TEST_ASSERT(!istype(locate(61, 61, z), /turf/simulated/shuttle/floor/voidcraft), "a solid turf is not roofed")
	GLOB.z_levels.Cut()
	GLOB.z_levels += levels_before
	test_driver_end()

/// A clearing landmark replaces the dense turfs around it with their base turf in one load, and leaves open turfs alone.
/datum/unit_test/dq_firstload_clearing_landmark_one_load

/datum/unit_test/dq_firstload_clearing_landmark_one_load/Run()
	test_driver_begin()
	var/z = dq_firstload_paths_z()
	var/list/walls = list()
	for(var/x in 20 to 24)
		walls[locate(x, 20, z)] = /turf/simulated/wall
	place_turfs(walls, label = "clearing test setup")
	TEST_ASSERT(locate(22, 20, z).density, "the setup walls are dense")
	// The landmark clears its surroundings when its init closes (find_docking_controller runs from its after_init).
	var/loads_before = GLOB.place_turfs_load_count
	var/obj/effect/shuttle_landmark/automatic/clearing/L = new(locate(22, 22, z))
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_before, 1, "the clearing was placed as one load")
	for(var/turf/T as anything in walls)
		var/turf/now = locate(T.x, T.y, T.z)
		if(get_dist(now, L) <= 10)
			TEST_ASSERT(!now.density, "the wall at [now.x],[now.y] was cleared")
	test_driver_end()

// ---- a placement made from a deferred map resolver, inside another placement's frame ----

/// Test marker whose map resolver defers (map_resolve_later) to a builder that places turfs itself, the way the turbolift builder does.
/obj/effect/dq_nested_place_marker
	name = "nested placement marker"

CAPABILITIES(/obj/effect/dq_nested_place_marker)
	map_resolver(GLOBAL_PROC_REF(dq_nested_place_resolve), vars = list())

/// The turfs the nested builder placed, for the test to read.
GLOBAL_LIST_EMPTY(dq_nested_placed)

/proc/dq_nested_place_resolve(atom/loc, path, list/varedits)
	map_resolve_later(GLOBAL_PROC_REF(dq_nested_place_build), get_turf(loc), path, varedits)
	return TRUE

/proc/dq_nested_place_build(turf/origin, path, list/varedits)
	var/list/types = list()
	for(var/dx in 1 to 3)
		types[locate(origin.x + dx, origin.y, origin.z)] = /turf/simulated/floor/tiled
	GLOB.dq_nested_placed += place_turfs(types, clear = FALSE, label = "nested placement")

/// A placement started by a resolver that runs while another placement's frame closes ends cleanly: both loads count, every turf initializes,
/// and the world is not left believing a map is loading.
/datum/unit_test/dq_firstload_nested_placement

/datum/unit_test/dq_firstload_nested_placement/Run()
	test_driver_begin()
	var/z = dq_firstload_paths_z()
	var/turf/at = locate(30, 30, z)
	var/loads_before = GLOB.place_turfs_load_count
	GLOB.dq_nested_placed.Cut()
	var/list/types = list()
	types[at] = /turf/simulated/floor/tiled
	var/list/things = list()
	things[at] = list(/obj/effect/dq_nested_place_marker)
	var/list/outer = place_turfs(types, things = things, label = "outer placement")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_before, 2, "the outer and the nested placement both ran")
	TEST_ASSERT_EQUAL(length(GLOB.dq_nested_placed), 3, "the nested builder placed its turfs")
	for(var/turf/T as anything in outer + GLOB.dq_nested_placed)
		TEST_ASSERT(T.flags & ATOM_INITIALIZED, "[T.x],[T.y] is initialized")
	var/obj/effect/dq_nested_place_marker/marker = locate() in locate(30, 30, z)
	TEST_ASSERT(!marker || (marker.flags & ATOM_INITIALIZED), "the marker is initialized or gone")
	// A third placement afterwards still runs as its own single load (the first did not leave a load open).
	var/loads_after = GLOB.place_turfs_load_count
	var/list/more = list()
	more[locate(40, 40, z)] = /turf/simulated/floor/tiled
	place_turfs(more, label = "after nested")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_after, 1, "a later placement is one load")
	test_driver_end()

/// A universe state that counts the turf changes it is told about.
/datum/universal_state/dq_turf_change_counter
	var/changes = 0

/datum/universal_state/dq_turf_change_counter/OnTurfChange(turf/NT)
	changes++

/// place_turfs(tell_universe = TRUE) tells the universe state about each turf it replaces, as ChangeTurf does; the default does not.
/datum/unit_test/dq_firstload_place_tells_universe

/datum/unit_test/dq_firstload_place_tells_universe/Run()
	test_driver_begin()
	var/z = dq_firstload_paths_z()
	var/datum/universal_state/real_state = GLOB.universe
	var/datum/universal_state/dq_turf_change_counter/counter = new
	GLOB.universe = counter
	var/before = counter.changes
	var/list/quiet = list()
	quiet[locate(10, 10, z)] = /turf/simulated/floor/tiled
	place_turfs(quiet, label = "quiet")
	TEST_ASSERT_EQUAL(counter.changes, before, "the default placement does not tell the universe")
	var/list/told = list()
	told[locate(11, 10, z)] = /turf/simulated/floor/tiled
	told[locate(12, 10, z)] = /turf/simulated/floor/tiled
	place_turfs(told, label = "told", tell_universe = TRUE)
	TEST_ASSERT_EQUAL(counter.changes - before, 2, "tell_universe tells the universe once per replaced turf")
	GLOB.universe = real_state
	test_driver_end()

/// A turbolift is built with its shaft placed as one load: floor on the first level, open space above, doors on the cells outside the shaft.
/datum/unit_test/dq_firstload_turbolift_one_load

/datum/unit_test/dq_firstload_turbolift_one_load/Run()
	test_driver_begin()
	var/z = dq_firstload_paths_z()
	var/z_above = dq_firstload_paths_z()
	TEST_ASSERT_EQUAL(z_above, z + 1, "the test world gave two consecutive levels")
	var/list/levels_before = GLOB.z_levels.Copy()
	while(length(GLOB.z_levels) < z_above - 1)
		GLOB.z_levels += FALSE
	GLOB.z_levels[z] = TRUE
	var/loads_before = GLOB.place_turfs_load_count
	var/list/varedits = list("depth" = 2, "areas_to_use" = list(/area/turbolift/port_deck_one, /area/turbolift/port_deck_two))
	turbolift_build(locate(20, 20, z), /obj/turbolift_map_holder, varedits)
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_before, 1, "the shaft was placed as one load")
	var/turf/inside = locate(21, 21, z)
	TEST_ASSERT(istype(inside, /turf/simulated/floor/tiled/dark), "the lift floor stands on the first level")
	TEST_ASSERT(inside.flags & ATOM_INITIALIZED, "the lift floor is initialized")
	TEST_ASSERT(isopenspace(locate(21, 21, z_above)), "the shaft is open space above")
	TEST_ASSERT(locate(/obj/structure/lift/panel) in locate(21, 21, z) || locate(/obj/structure/lift/panel) in range(2, inside), "the lift has its panel")
	GLOB.z_levels.Cut()
	GLOB.z_levels += levels_before
	test_driver_end()
