// The map reader's load at a location (code/content/maps/reader.dm): a chunk plans its turfs and contents as data and places them together
// (place_turfs_in_load) in the load's one init frame. Proved with ChangeTurf counts, load counts and frame counts, and by what a template placed over
// used ground leaves behind.

/// The turfs of a rectangle that are not space.
/proc/dq_firstload_non_space(z, x1, y1, x2, y2)
	var/n = 0
	for(var/turf/T as anything in block(locate(x1, y1, z), locate(x2, y2, z)))
		if(!istype(T, /turf/space))
			n++
	return n

/// Everything not yet initialized in a rectangle: turfs and what stands on them.
/proc/dq_firstload_uninitialized(z, x1, y1, x2, y2)
	var/n = 0
	for(var/turf/T as anything in block(locate(x1, y1, z), locate(x2, y2, z)))
		if(!(T.flags & ATOM_INITIALIZED))
			n++
		for(var/atom/movable/AM as anything in T)
			if(!(AM.flags & ATOM_INITIALIZED))
				n++
	return n

/// A small template placed at a location: every ChangeTurf of the load goes through the planned placement, it opens no load of its own, and it
/// initializes in one frame.
/datum/unit_test/dq_firstload_reader_small_template

/datum/unit_test/dq_firstload_reader_small_template/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/blank = new
	var/z = blank.load_new_z()
	var/datum/map_template/unit_tests/template = new
	var/changes_before = GLOB.turf_change_calls
	var/replaced_before = GLOB.place_turfs_replaced
	var/loads_before = GLOB.place_turfs_load_count
	SSatoms.batch_trace = list()
	TEST_ASSERT(template.load(locate(20, 20, z)), "the template loaded at a location")
	var/list/frames = SSatoms.batch_trace
	SSatoms.batch_trace = null
	var/x2 = 20 + template.width - 1
	var/y2 = 20 + template.height - 1
	var/changes = GLOB.turf_change_calls - changes_before
	log_test("FIRSTLOAD reader small template [template.width]x[template.height]: [changes] ChangeTurf calls, [length(frames)] init frame(s)")
	TEST_ASSERT(changes >= dq_firstload_non_space(z, 20, 20, x2, y2), "every turf the template made was placed")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_replaced - replaced_before, changes, "every ChangeTurf of the load went through the planned placement")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_load_count - loads_before, 0, "the reader opens no load of its own")
	TEST_ASSERT_EQUAL(length(frames), 1, "the template initialized in one frame")
	TEST_ASSERT_EQUAL(dq_firstload_uninitialized(z, 20, 20, x2, y2), 0, "everything the template made is initialized")
	test_driver_end()

/// A POI-sized template (the derelict engine bay): the same counts.
/datum/unit_test/dq_firstload_reader_poi_template

/datum/unit_test/dq_firstload_reader_poi_template/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/blank = new
	var/z = blank.load_new_z()
	var/datum/map_template/expedition_engine/template = new
	var/changes_before = GLOB.turf_change_calls
	var/replaced_before = GLOB.place_turfs_replaced
	SSatoms.batch_trace = list()
	TEST_ASSERT(template.load(locate(30, 30, z)), "the engine bay loaded at a location")
	var/list/frames = SSatoms.batch_trace
	SSatoms.batch_trace = null
	var/x2 = 30 + template.width - 1
	var/y2 = 30 + template.height - 1
	var/changes = GLOB.turf_change_calls - changes_before
	log_test("FIRSTLOAD reader engine bay [template.width]x[template.height]: [changes] ChangeTurf calls, [length(frames)] init frame(s)")
	TEST_ASSERT(changes >= dq_firstload_non_space(z, 30, 30, x2, y2), "every turf the bay made was placed")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_replaced - replaced_before, changes, "every ChangeTurf of the load went through the planned placement")
	TEST_ASSERT_EQUAL(length(frames), 1, "the bay initialized in one frame")
	TEST_ASSERT_EQUAL(dq_firstload_uninitialized(z, 30, 30, x2, y2), 0, "everything the bay made is initialized")
	test_driver_end()

/// A template loaded over used ground ends up as the map says: a floor of the same type that was broken, burnt and renamed comes back pristine.
/datum/unit_test/dq_firstload_reader_over_used_ground

/datum/unit_test/dq_firstload_reader_over_used_ground/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/blank = new
	var/z = blank.load_new_z()
	var/datum/map_template/unit_tests/template = new
	TEST_ASSERT(template.load(locate(20, 20, z)), "the template loaded")
	var/turf/simulated/floor/victim
	for(var/turf/simulated/floor/F in block(locate(20, 20, z), locate(20 + template.width - 1, 20 + template.height - 1, z)))
		if(F.flooring && (F.flooring.flags & TURF_CAN_BREAK) && (F.flooring.flags & TURF_CAN_BURN))
			victim = F
			break
	TEST_ASSERT_NOTNULL(victim, "the template has a floor that can break and burn")
	var/x = victim.x
	var/y = victim.y
	var/floor_type = victim.type
	var/pristine_name = victim.name
	victim.break_tile()
	victim.burn_tile(1000)
	victim.name = "scorched floor"
	TEST_ASSERT(!isnull(victim.broken) || !isnull(victim.burnt), "the floor was damaged")
	TEST_ASSERT(template.load(locate(20, 20, z)), "the template loaded again over the damaged floor")
	var/turf/simulated/floor/after = locate(x, y, z)
	TEST_ASSERT_EQUAL(after.type, floor_type, "the same floor type")
	TEST_ASSERT_NULL(after.broken, "the floor is no longer broken")
	TEST_ASSERT_NULL(after.burnt, "the floor is no longer burnt")
	TEST_ASSERT_EQUAL(after.name, pristine_name, "the floor has the map's name again")
	test_driver_end()

/// A template's size comes from the build's bounds file when its map is unchanged (vg_file_size() against the recorded
/// size, no read), and matches what parsing the map says.
/datum/unit_test/dq_template_bounds_from_build_match_parse

/datum/unit_test/dq_template_bounds_from_build_match_parse/Run()
	var/checked = 0
	for(var/datum/map_template/shelter/T as anything in subtypesof(/datum/map_template/shelter))
		var/path = initial(T.mappath)
		if(!path || !fexists(path))
			continue
		TEST_ASSERT_EQUAL(vg_file_size(path), length(file(path)), "vg_file_size() of [path] is its length")
		// The bounds file is the build's (data/, beside the server's .dmb): a test world run from another directory has none.
		var/list/cached = build_time_template_bounds(path)
		if(cached)
			var/datum/parsed_map/parsed = new /datum/parsed_map/working(file(path))
			TEST_ASSERT_EQUAL(cached[MAP_MAXX], parsed.bounds[MAP_MAXX], "[path] width")
			TEST_ASSERT_EQUAL(cached[MAP_MAXY], parsed.bounds[MAP_MAXY], "[path] height")
			qdel(parsed)
		if(++checked >= 5)
			break
	TEST_ASSERT(checked > 0, "no shelter map to check")
	TEST_ASSERT_NULL(vg_file_size("maps/does_not_exist.dmm"), "a missing file has no size")
