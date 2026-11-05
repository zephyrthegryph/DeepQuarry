// random_map apply (code/content/random_map/random_map.dm): a map of final turfs is planned as data and placed as one load, then its spawns run
// over the placed cells. Proved with ChangeTurf and frame counts and behaviour (connectivity, no spawn inside a wall), not golden maps.

/// A spawn the test maps make on a cell (a test-only effect).
/obj/effect/dq_firstload_spawn_marker
	name = "first load spawn marker"

/// An automata map that marks every floor cell and says when it has finished applying.
/datum/random_map/automata/dq_firstload_marked
	descriptor = "first load marked caves"
	iterations = 4
	limit_x = 40
	limit_y = 40
	var/finished = FALSE

/datum/random_map/automata/dq_firstload_marked/get_additional_spawns(value, turf/T)
	if(value == FLOOR_CHAR)
		new /obj/effect/dq_firstload_spawn_marker(T)

/datum/random_map/automata/dq_firstload_marked/apply_finished()
	finished = TRUE

/// The open (non-dense) turfs of a rectangle that can be reached from `start` over open turfs, as a set.
/proc/dq_firstload_reachable(z, x1, y1, x2, y2, turf/start)
	var/list/seen = list()
	var/list/frontier = list(start)
	seen[start] = TRUE
	while(length(frontier))
		var/turf/at = frontier[length(frontier)]
		frontier.len--
		for(var/dir in list(NORTH, SOUTH, EAST, WEST))
			var/turf/next = get_step(at, dir)
			if(!next || seen[next] || next.density || next.x < x1 || next.x > x2 || next.y < y1 || next.y > y2)
				continue
			seen[next] = TRUE
			frontier += next
	return seen

/// A maze is applied in one frame with one ChangeTurf per cell; its open cells are one connected passage and its walls are dense.
/datum/unit_test/dq_firstload_random_map_maze

/datum/unit_test/dq_firstload_random_map_maze/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	var/changes_before = GLOB.turf_change_calls
	var/loads_before = GLOB.place_turfs_load_count
	SSatoms.batch_trace = list()
	var/datum/random_map/maze/M = new(7, 10, 10, z, 41, 41, FALSE, TRUE)
	var/list/frames = SSatoms.batch_trace
	SSatoms.batch_trace = null
	var/cells = M.limit_x * M.limit_y
	TEST_ASSERT_EQUAL(GLOB.turf_change_calls - changes_before, cells, "one ChangeTurf per cell of the maze")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_before, 1, "the maze was placed as one load")
	TEST_ASSERT_EQUAL(length(frames), 1, "the maze initialized in one frame")
	var/open = 0
	var/turf/first_open
	for(var/x in 1 to M.limit_x)
		for(var/y in 1 to M.limit_y)
			var/turf/T = locate(9 + x, 9 + y, z)
			TEST_ASSERT(T.flags & ATOM_INITIALIZED, "[T.x],[T.y] is initialized")
			var/value = M.map[M.get_map_cell(x, y)]
			if(value == FLOOR_CHAR)
				TEST_ASSERT(!T.density, "a floor cell at [T.x],[T.y] is open")
				TEST_ASSERT(istype(T, M.floor_type), "a floor cell at [T.x],[T.y] is a floor")
				open++
				if(!first_open)
					first_open = T
			else
				TEST_ASSERT(T.density, "a wall cell at [T.x],[T.y] is dense")
	TEST_ASSERT(open > 0, "the maze has open cells")
	var/list/reached = dq_firstload_reachable(z, 10, 10, 10 + M.limit_x - 1, 10 + M.limit_y - 1, first_open)
	TEST_ASSERT_EQUAL(length(reached), open, "every open cell of the maze is reachable from the first")
	test_driver_end()

/// A map's spawns come after its turfs and only on open cells; the async form reports when it is finished.
/datum/unit_test/dq_firstload_random_map_spawns

/datum/unit_test/dq_firstload_random_map_spawns/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	var/changes_before = GLOB.turf_change_calls
	var/datum/random_map/automata/dq_firstload_marked/M = new(null, 10, 10, z, 40, 40, FALSE, TRUE)
	for(var/pass in 1 to 4000)
		if(M.finished)
			break
		test_time(1)
	TEST_ASSERT(M.finished, "the map finished applying")
	var/replaced = GLOB.turf_change_calls - changes_before
	TEST_ASSERT(replaced > 0 && replaced <= 40 * 40, "at most one ChangeTurf per cell ([replaced])")
	var/floors = 0
	var/markers = 0
	for(var/x in 1 to 40)
		for(var/y in 1 to 40)
			var/turf/T = locate(9 + x, 9 + y, z)
			var/has_marker = !!(locate(/obj/effect/dq_firstload_spawn_marker) in T)
			if(M.map[M.get_map_cell(x, y)] == FLOOR_CHAR)
				floors++
				TEST_ASSERT(!T.density, "a floor cell at [T.x],[T.y] is open")
				TEST_ASSERT(has_marker, "a floor cell at [T.x],[T.y] got its spawn")
				markers++
			else
				TEST_ASSERT(T.density, "a wall cell at [T.x],[T.y] is dense")
				TEST_ASSERT(!has_marker, "no spawn inside the wall at [T.x],[T.y]")
	TEST_ASSERT(floors > 0, "the map has floor cells")
	TEST_ASSERT_EQUAL(markers, floors, "one spawn per floor cell")
	test_driver_end()
