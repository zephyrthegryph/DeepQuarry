#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/datum/generated_station_materializer/dq_work_state/generation_checkpoint(phase, progress, force_yield = FALSE)
	return TRUE

/datum/unit_test/dq_generated_plan_live_work/seal_queue/Run()
	var/datum/generated_station_materializer/dq_work_state/M = allocate(/datum/generated_station_materializer/dq_work_state)
	var/datum/generated_station_tile_plan/P = allocate(/datum/generated_station_tile_plan, 5, 5, M)
	TEST_ASSERT(P.validate_seal_step(null), "The actual validator yields after seeding its work queue")
	var/list/queue = P.seal_open
	var/list/order = queue.Copy()
	var/count = P.seal_open_count
	TEST_ASSERT(count > 0, "The real seeded queue is nonempty")
	changed(P, CHANGE_EXPLICIT)
	TEST_ASSERT_EQUAL(P.seal_open, queue, "An unrelated old publication cannot drop live queued work")
	TEST_ASSERT_EQUAL(P.seal_open_count, count, "The saved queue cursor remains paired with its queue")
	for(var/i in 1 to length(order))
		TEST_ASSERT_EQUAL(P.seal_open[i], order[i], "Publication preserves actual queue order at [i]")
	var/cursor = TRUE
	var/slices = 0
	while(!isnull(cursor) && slices++ < 100)
		cursor = P.validate_seal_step(cursor)
	TEST_ASSERT_NULL(cursor, "The real validator resumes its preserved queue and finishes")
	TEST_ASSERT_EQUAL(length(P.errors), 0, "An all-exterior plan finishes without a false pressure-hull failure")

/datum/unit_test/dq_generated_plan_live_work/hull_coordinates/Run()
	var/datum/generated_station_materializer/dq_work_state/M = allocate(/datum/generated_station_materializer/dq_work_state)
	var/datum/generated_station_tile_plan/P = allocate(/datum/generated_station_tile_plan, 5, 5, M)
	TEST_ASSERT(P.claim(3, 3, "fixture", "room", GENERATED_STATION_TILE_FLOOR, /turf/simulated/floor/tiled, null), "Real plan claim creates the pressure-bearing floor")
	var/list/cursor
	var/slices = 0
	while(!length(P.hull_coordinates) && slices++ < 100)
		cursor = P.derive_hull_step(cursor)
	TEST_ASSERT(length(P.hull_coordinates) > 0 && !isnull(cursor), "Real hull derivation yields with accumulated coordinates")
	var/list/coordinates = P.hull_coordinates
	var/list/saved = coordinates.Copy()
	changed(P, CHANGE_EXPLICIT)
	TEST_ASSERT_EQUAL(P.hull_coordinates, coordinates, "Publication preserves the actual coordinate-map identity")
	for(var/key in saved)
		TEST_ASSERT_EQUAL(P.hull_coordinates[key], saved[key], "Each saved coordinate row keeps its identity")
	while(!isnull(cursor) && slices++ < 200)
		cursor = P.derive_hull_step(cursor)
	TEST_ASSERT_NULL(cursor, "Hull derivation resumes and finishes after publication")
	TEST_ASSERT_EQUAL(length(P.errors), 0, "The actual claimed hull remains valid")

/datum/unit_test/dq_generated_plan_live_work/borrowed_corner_policy/Run()
	var/datum/generated_station_tile_plan/P = allocate(/datum/generated_station_tile_plan, 3, 3, null)
	var/datum/generated_station_tile_intent/I = P.tile(2, 2)
	TEST_ASSERT_EQUAL(owner_of(I), P, "The real tile ledger owns the intent before linking it")
	rel_add(P, nameof(P.hull_corners), I)
	TEST_ASSERT_EQUAL(P.hull_corners[1], I, "The declared native corner relation refers to the actual intent")
	changed(P, CHANGE_EXPLICIT)
	TEST_ASSERT_EQUAL(P.hull_corners[1], I, "Unrelated publication preserves the live borrowed corner")
	rel_clear(P, nameof(P.hull_corners))
	TEST_ASSERT(!QDELETED(I), "Clearing the borrowed relation does not delete the plan's owned tile")
	TEST_ASSERT_EQUAL(owner_of(I), P, "Corner clearing preserves genuine tile custody")
#endif
