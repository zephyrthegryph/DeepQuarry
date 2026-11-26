// The world opacity layer (code/domains/verdigris/sight/) and the Rust sight walk over it. The walk's own properties (symmetry,
// lit wall faces, no light through diagonal wall seams, no flicker on a step, determinism) are Rust tests in
// verdigris/core/src/propagate/view.rs; these check the DM feed and report how it differs from BYOND's view().

/// An opaque wall built on the map reaches the Rust layer: the floor behind it goes dark, the wall face stays seen, and it
/// all comes back when the wall goes.
/datum/unit_test/dq_sight_layer_follows_opacity

/datum/unit_test/dq_sight_layer_follows_opacity/Run()
	var/turf/center = run_loc_floor_bottom_left
	var/turf/wall_spot = locate(center.x + 1, center.y, center.z)
	var/turf/behind = locate(center.x + 2, center.y, center.z)
	TEST_ASSERT(wall_spot && behind && !wall_spot.directional_opacity && !behind.directional_opacity, "the test floor has two clear turfs east of it")
	TEST_ASSERT(behind in sight_view_turfs(center, 3), "the clear floor two tiles east is seen")
	var/obj/structure/sight_test_blocker/B = allocate(/obj/structure/sight_test_blocker, wall_spot)
	TEST_ASSERT(wall_spot.directional_opacity, "the opaque blocker made its turf opaque")
	var/list/seen = sight_view_turfs(center, 3)
	TEST_ASSERT(wall_spot in seen, "the blocker's turf (a wall face) is seen")
	TEST_ASSERT(!(behind in seen), "the floor straight behind the blocker is dark")
	qdel(B)
	TEST_ASSERT(behind in sight_view_turfs(center, 3), "the floor is seen again once the blocker is gone")

/obj/structure/sight_test_blocker
	name = "sight test blocker"
	opacity = TRUE
	anchored = TRUE

/// Information only (never fails on a difference): how the Rust walk differs from BYOND's view() across the test map, split
/// into floors and walls each side sees alone. Ours is symmetric shadowcasting by design, not a copy of view().
/datum/unit_test/dq_sight_view_diff_report

/datum/unit_test/dq_sight_view_diff_report/Run()
	var/z = run_loc_floor_bottom_left.z
	var/list/ranges = list(2, 4, 7)
	var/compared = 0
	var/differ = 0
	var/list/counts = list("ours_floor" = 0, "ours_wall" = 0, "byond_floor" = 0, "byond_wall" = 0)
	var/list/samples = list()
	var/byond_ms = 0
	var/ours_ms = 0
	for(var/x = 2, x <= world.maxx - 1, x += 3)
		for(var/y = 2, y <= world.maxy - 1, y += 3)
			var/turf/center = locate(x, y, z)
			if(!center)
				continue
			for(var/range in ranges)
				var/start = TICK_USAGE
				var/old_lum = center.luminosity
				center.luminosity = range
				var/list/byond = list()
				for(var/turf/T in view(range, center))
					byond[T] = TRUE
				center.luminosity = old_lum
				byond_ms += TICK_USAGE_TO_MS(start)
				start = TICK_USAGE
				var/list/ours_list = sight_view_turfs(center, range)
				ours_ms += TICK_USAGE_TO_MS(start)
				var/list/ours = list()
				for(var/turf/T as anything in ours_list)
					ours[T] = TRUE
				compared++
				var/list/only_ours = list()
				var/list/only_byond = list()
				for(var/turf/T as anything in ours)
					if(!byond[T])
						only_ours += T
						counts[T.directional_opacity ? "ours_wall" : "ours_floor"]++
				for(var/turf/T as anything in byond)
					if(!ours[T])
						only_byond += T
						counts[T.directional_opacity ? "byond_wall" : "byond_floor"]++
				if(length(only_ours) || length(only_byond))
					differ++
					if(length(samples) < 12)
						samples += "centre [x],[y] range [range]: ours only [offsets(only_ours, x, y)]; BYOND only [offsets(only_byond, x, y)]"
	log_test("SIGHT DIFF REPORT: [compared] views, [differ] differ; cells seen only by ours: [counts["ours_floor"]] floors, [counts["ours_wall"]] walls; only by BYOND: [counts["byond_floor"]] floors, [counts["byond_wall"]] walls")
	log_test("SIGHT DIFF REPORT: time over these views: BYOND view() [round(byond_ms, 0.1)] ms, Rust sight_view_turfs() [round(ours_ms, 0.1)] ms")
	for(var/line in samples)
		log_test("SIGHT DIFF SAMPLE [line]")
	TEST_ASSERT(compared > 100, "too few views compared ([compared])")

/datum/unit_test/dq_sight_view_diff_report/proc/offsets(list/turfs, x, y)
	var/list/out = list()
	for(var/turf/T as anything in turfs)
		out += "([T.x - x],[T.y - y][T.directional_opacity ? " wall" : ""])"
	return jointext(out, " ")
