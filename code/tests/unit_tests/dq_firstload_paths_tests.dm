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
