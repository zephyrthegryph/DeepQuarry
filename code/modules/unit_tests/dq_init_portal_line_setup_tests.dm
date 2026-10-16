// Real mapped-neighbour topology is linked before the existing after_init pairing callback.
/datum/unit_test/dq_init_portal_line_setup
/datum/unit_test/dq_init_portal_line_setup/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/effect/map_effect/portal/line/L = allocate(/obj/effect/map_effect/portal/line, get_step(T, EAST))
	var/obj/effect/map_effect/portal/line/R = allocate(/obj/effect/map_effect/portal/line, get_step(T, WEST))
	var/obj/effect/map_effect/portal/master/M = allocate(/obj/effect/map_effect/portal/master, T)
	TEST_ASSERT_EQUAL(L.my_master, M, "The real contiguous east line links during construction")
	TEST_ASSERT_EQUAL(R.my_master, M, "The real contiguous west line links during construction")
	TEST_ASSERT_EQUAL(length(M.portal_lines), 2, "Both actual lines join the master's inverse relation exactly once")
	qdel(M)
	TEST_ASSERT(!QDELETED(L) && !QDELETED(R), "Mapped lines remain borrowed, not owned by the master")
	TEST_ASSERT_NULL(L.my_master, "Master deletion clears the actual inverse endpoint")
