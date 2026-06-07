// Quarry mob-spawn tests.
//
// Exercises the predicates that gate mob placement: safe-room check,
// and the mini spawn loop on a small patch so we catch the case where
// every tile gets skipped and the layer ends up empty.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// --- safe-room predicate: plain floor returns FALSE -------------------

/datum/unit_test/dq_quarry_tile_is_safe_plain_floor

/datum/unit_test/dq_quarry_tile_is_safe_plain_floor/Run()
	var/turf/T = _dq_quarry_test_turf()
	TEST_ASSERT_NOTNULL(T, "no test turf available on z=1")
	// Force to a generic floor and relocate to a fresh empty area so
	// the area truly has no APC (the entry area carries a hand-placed
	// APC for the map-test machinery requirement).
	T = T.ChangeTurf(/turf/simulated/floor)
	TEST_ASSERT_NOTNULL(T, "couldn't ChangeTurf to /turf/simulated/floor")
	var/area/empty_area = new /area/space()
	ChangeArea(T, empty_area)
	var/safe = _quarry_tile_is_safe(T)
	TEST_ASSERT(!safe, "expected plain floor in non-APC area to be unsafe (spawnable), got safe=[safe]; area=[get_area(T)?.type] apc=[get_area(T)?.apc]")


// --- safe-room predicate: null turf returns FALSE ---------------------

/datum/unit_test/dq_quarry_tile_is_safe_null_turf

/datum/unit_test/dq_quarry_tile_is_safe_null_turf/Run()
	var/safe = _quarry_tile_is_safe(null)
	TEST_ASSERT(!safe, "expected null turf to return FALSE, got [safe]")


// --- mini spawn loop: places mobs on a patch ---------------------------
//
// Replicates the spawn pass from generate_layer on a tiny 8x8 patch
// of floor, then verifies that mobs were actually placed. If
// _quarry_tile_is_safe is over-blocking, this fails. If pickweight
// is failing on the mob_table format, this fails. If the loop
// structure is broken, this fails.

/datum/unit_test/dq_quarry_spawn_pass_places_mobs

/datum/unit_test/dq_quarry_spawn_pass_places_mobs/Run()
	// Prepare an 8x8 patch of floor. Relocate to a fresh empty area
	// so _quarry_tile_is_safe doesn't see the entry area's APC.
	var/turf/anchor = _dq_quarry_test_turf()
	TEST_ASSERT_NOTNULL(anchor, "no test turf available on z=1")
	var/area/empty_area = new /area/space()
	var/x0 = max(2, anchor.x - 3)
	var/y0 = max(2, anchor.y - 3)
	var/list/floors = list()
	for(var/dx in 0 to 7)
		for(var/dy in 0 to 7)
			var/turf/T = locate(x0 + dx, y0 + dy, anchor.z)
			if(!isturf(T))
				continue
			// Strip whatever's on it so the spawn loop's safety
			// checks see clean tiles.
			for(var/atom/movable/AM in T)
				if(ismob(AM))
					continue
				qdel(AM)
			T = T.ChangeTurf(/turf/simulated/floor)
			if(isturf(T))
				ChangeArea(T, empty_area)
				floors += T
	TEST_ASSERT(length(floors) >= 16, "couldn't prepare patch; got [length(floors)] floors")

	// Replica of the spawn loop body. If a real bug exists in the
	// production loop's logic, mirror the change here too — that's
	// the cost of testing without invoking the full generate_layer.
	var/list/mob_table = list(/mob/living/simple_mob/animal/passive/mouse/rat = 100)
	var/want = 10
	var/spawned = 0
	var/list/candidates = floors.Copy()
	while(spawned < want && length(candidates))
		var/turf/T = pick(candidates)
		candidates -= T
		if(_quarry_tile_is_safe(T))
			continue
		var/mob_type = pickweight(mob_table)
		if(mob_type)
			new mob_type(T)
		spawned++

	// Count mobs actually present on the patch.
	var/found = 0
	for(var/turf/T as anything in floors)
		for(var/mob/M in T)
			if(istype(M, /mob/living/simple_mob/animal/passive/mouse/rat))
				found++

	TEST_ASSERT(found >= want, "expected [want] mice on the patch, found [found]")

	// Clean up so subsequent tests don't see the rats.
	for(var/turf/T as anything in floors)
		for(var/mob/living/simple_mob/animal/passive/mouse/rat/R in T)
			qdel(R)


#endif
