// place_turfs() (code/content/maps/place_turfs.dm): a site placed as one load ends up the way the per-turf ChangeTurf path leaves it.

/// What a region of turfs is, the properties a first load must leave the same however it was built: the type, whether it initialized, its area,
/// lighting object, air, wall joins, and what stands on it.
/proc/dq_firstload_fingerprint(z, x1, y1, x2, y2)
	var/list/rows = list()
	for(var/y in y1 to y2)
		for(var/x in x1 to x2)
			var/turf/T = locate(x, y, z)
			var/list/stuff = list()
			for(var/atom/movable/AM as anything in T)
				// A floor drops dirt at random when it initializes: not a function of how the site was built.
				if(istype(AM, /obj/effect/decal/cleanable))
					continue
				stuff += "[AM.type]:[(AM.flags & ATOM_INITIALIZED) ? 1 : 0]"
			sortTim(stuff, GLOBAL_PROC_REF(cmp_text_asc))
			var/air = 0
			var/turf/open/O = T
			if(istype(O) && O.air)
				air = 1
			var/joins = 0
			var/turf/simulated/wall/W = T
			if(istype(W))
				joins = W.smooth_mask
			rows += "[x - x1],[y - y1]:[T.type] init=[(T.flags & ATOM_INITIALIZED) ? 1 : 0] area=[T.loc.type] light=[T.lighting_object ? 1 : 0] air=[air] joins=[joins] [stuff.Join("+")]"
	return rows

/// A square site of final turfs: a wall ring, alternating floors inside, a closet on some floors.
/proc/dq_firstload_site_plan(z, x0, y0, size, list/types, list/things)
	for(var/dx in 0 to size - 1)
		for(var/dy in 0 to size - 1)
			var/turf/T = locate(x0 + dx, y0 + dy, z)
			if(dx == 0 || dy == 0 || dx == size - 1 || dy == size - 1)
				types[T] = /turf/simulated/wall
			else
				types[T] = ((dx + dy) % 2) ? /turf/simulated/floor/plating : /turf/simulated/floor/tiled
				if(!((dx * 7 + dy) % 5))
					things[T] = list(/obj/structure/closet)

/// place_turfs() leaves a site the way the per-turf ChangeTurf path does (types, initialization, areas, lighting, air, wall joins, contents), in one
/// frame, with one ChangeTurf per turf it replaced and none for a turf that was already final.
/datum/unit_test/dq_firstload_place_turfs_matches_changeturf

/datum/unit_test/dq_firstload_place_turfs_matches_changeturf/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	var/size = 30 // 900 turfs and the closets: two init chunks
	// The old way: a ChangeTurf per turf, its contents made after.
	var/list/old_types = list()
	var/list/old_things = list()
	dq_firstload_site_plan(z, 20, 20, size, old_types, old_things)
	for(var/turf/T as anything in old_types)
		old_types[T] = T.ChangeTurf(old_types[T], tell_universe = FALSE)
	for(var/turf/T as anything in old_things)
		for(var/path in old_things[T])
			new path(T)
	// The new way, on another part of the level.
	var/list/types = list()
	var/list/things = list()
	dq_firstload_site_plan(z, 60, 20, size, types, things)
	var/changes_before = GLOB.turf_change_calls
	var/loads_before = GLOB.place_turfs_loads
	var/replaced_before = GLOB.place_turfs_replaced
	SSatoms.batch_trace = list()
	var/list/placed = place_turfs(types, things = things, label = "unit test")
	var/list/frames = SSatoms.batch_trace
	SSatoms.batch_trace = null
	TEST_ASSERT_EQUAL(length(placed), size * size, "every turf of the site was replaced")
	TEST_ASSERT_EQUAL(GLOB.turf_change_calls - changes_before, size * size, "one ChangeTurf per replaced turf")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_replaced - replaced_before, size * size, "the replaced counter")
	TEST_ASSERT_EQUAL(GLOB.place_turfs_loads - loads_before, 1, "one load")
	TEST_ASSERT_EQUAL(length(frames), 1, "the site initialized in one frame")
	var/datum/materialize_batch/frame = frames[1]
	TEST_ASSERT(frame.chunks >= 2, "900 turfs and their closets initialize in two or more chunks of one frame")
	var/list/old_rows = dq_firstload_fingerprint(z, 20, 20, 20 + size - 1, 20 + size - 1)
	var/list/new_rows = dq_firstload_fingerprint(z, 60, 20, 60 + size - 1, 20 + size - 1)
	TEST_ASSERT_EQUAL(length(new_rows), length(old_rows), "same number of turfs")
	var/differing = 0
	for(var/i in 1 to length(old_rows))
		if(old_rows[i] != new_rows[i])
			if(++differing <= 5)
				log_test("FIRSTLOAD placed site differs from the ChangeTurf one at row [i]: [old_rows[i]] VS [new_rows[i]]")
	TEST_ASSERT_EQUAL(differing, 0, "rows that differ")
	// Placing the same site again changes nothing: every turf is already its final type.
	var/replaced_mid = GLOB.place_turfs_replaced
	var/changes_mid = GLOB.turf_change_calls
	var/list/again_types = list()
	var/list/again_things = list()
	dq_firstload_site_plan(z, 60, 20, size, again_types, again_things)
	place_turfs(again_types, label = "unit test again", clear = FALSE)
	TEST_ASSERT_EQUAL(GLOB.place_turfs_replaced - replaced_mid, 0, "a turf already final is not replaced")
	TEST_ASSERT_EQUAL(GLOB.turf_change_calls - changes_mid, 0, "and costs no ChangeTurf")
	test_driver_end()

/// place_turfs_async() does the same work in steps and then reports the new turfs to its caller.
/datum/unit_test/dq_firstload_place_turfs_async
	var/list/reported

/datum/unit_test/dq_firstload_place_turfs_async/proc/done(list/placed)
	reported = placed

/datum/unit_test/dq_firstload_place_turfs_async/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	var/list/types = list()
	var/list/things = list()
	dq_firstload_site_plan(z, 60, 60, 20, types, things)
	place_turfs_async(types, things = things, then = PROC_REF(done), owner = src, label = "unit test async")
	TEST_ASSERT_NULL(reported, "nothing happens before the kernel pass")
	for(var/pass in 1 to 4000)
		if(reported)
			break
		test_time(1)
	TEST_ASSERT_EQUAL(length(reported), 400, "the caller got the new turfs")
	for(var/turf/T as anything in reported)
		TEST_ASSERT(T.flags & ATOM_INITIALIZED, "[T.type] at [T.x],[T.y] is initialized when the caller hears")
	test_driver_end()
