#if defined(UNIT_TESTS)
// What a walking light costs per step (overlay_lighting): updates asked for, view reads, turfs whose lumcount is written.

/datum/unit_test/dq_overlay_light_step

/// A human walking a row with a lit pen in hand at `range`; returns the counters per step as a list(updates, views, written).
/datum/unit_test/dq_overlay_light_step/proc/walk_cost(range, steps, held)
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/carrier = allocate(/mob/living/carbon/human, start)
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, held ? carrier : start)
	set_glow(lamp, GLOW(range, 1, "#ffffff"), TRUE)
	var/datum/overlay_lighting/light = lamp.overlay_light
	TEST_ASSERT_NOTNULL(light, "the lit pen has an overlay light")
	var/updates = light.stat_updates
	var/views = light.stat_views
	var/written = light.stat_turfs_written
	var/atom/movable/walker = held ? carrier : lamp
	var/done = 0
	for(var/i in 1 to steps)
		var/turf/next = get_step(walker, EAST)
		if(!next)
			break
		walker.forceMove(next)
		done++
	TEST_ASSERT(done >= steps - 2, "the walker had room to walk ([done] of [steps] steps)")
	return list((light.stat_updates - updates) / done, (light.stat_views - views) / done, (light.stat_turfs_written - written) / done, done)

/datum/unit_test/dq_overlay_light_step/Run()
	for(var/held in list(TRUE, FALSE))
		for(var/range in list(2, 4, 6))
			var/list/cost = walk_cost(range, 8, held)
			log_test("OVERLAY LIGHT STEP held=[held] range=[range]: per step updates [cost[1]], view reads [cost[2]], turfs written [cost[3]] over [cost[4]] steps")
			TEST_ASSERT(cost[2] <= 1, "at most one view read per step (held=[held] range=[range]: [cost[2]])")
			TEST_ASSERT(cost[3] <= 2 * (2 * range + 1), "turfs written per step stay within the edge strips (held=[held] range=[range]: [cost[3]])")

/// Parity: after every step of a walk (and a turn back) the lit set is what a fresh read of the sight layer from the light's turf gives, and every turf's
/// dynamic_lumcount is what it was before the light plus the light's power if the turf is lit: a rebuild from nothing and the delta agree.
/datum/unit_test/dq_overlay_light_step_parity

/datum/unit_test/dq_overlay_light_step_parity/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/list/baseline = list()
	for(var/turf/T in block(locate(max(1, start.x - 1), max(1, start.y - 1), start.z), locate(min(world.maxx, start.x + 16), min(world.maxy, start.y + 8), start.z)))
		baseline[T] = T.dynamic_lumcount
	for(var/range in list(2, 5))
		var/mob/living/carbon/human/carrier = allocate(/mob/living/carbon/human, start)
		var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight, carrier)
		set_glow(lamp, GLOW(range, 1, "#ffffff"), TRUE)
		var/datum/overlay_lighting/light = lamp.overlay_light
		TEST_ASSERT_NOTNULL(light, "the lit pen has an overlay light")
		var/list/route = list(EAST, EAST, EAST, NORTH, EAST, EAST, SOUTH, WEST, WEST, EAST, EAST, EAST)
		var/steps = 0
		for(var/dir in route)
			var/turf/next = get_step(carrier, dir)
			if(!next || !(next in baseline))
				continue
			carrier.forceMove(next)
			steps++
			var/list/expected = list()
			var/atom/lit_from = light.directional_atom || light.current_holder()
			for(var/turf/T as anything in sight_view_turfs(get_turf(lit_from), light.lumcount_range))
				expected[T] = TRUE
			TEST_ASSERT_EQUAL(length(light.affected_turfs), length(expected), "step [steps] range [range]: the lit set has the turfs a fresh read gives")
			for(var/turf/T as anything in expected)
				TEST_ASSERT(light.affected_turfs[T], "step [steps] range [range]: ([T.x],[T.y]) is lit")
			for(var/turf/T as anything in baseline)
				var/want = baseline[T] + (expected[T] ? light.lum_power : 0)
				TEST_ASSERT(abs(T.dynamic_lumcount - want) < 0.001, "step [steps] range [range]: ([T.x],[T.y]) lumcount [T.dynamic_lumcount] is [want]")
		TEST_ASSERT(steps >= 6, "the walk had room ([steps] steps)")
		log_test("OVERLAY LIGHT PARITY range [range]: [steps] steps agree; [light.lighting_trace()]")
		qdel(lamp)
		qdel(carrier)
	for(var/turf/T as anything in baseline)
		TEST_ASSERT(abs(T.dynamic_lumcount - baseline[T]) < 0.001, "both lights gone, ([T.x],[T.y]) is back to its lumcount")
#endif
