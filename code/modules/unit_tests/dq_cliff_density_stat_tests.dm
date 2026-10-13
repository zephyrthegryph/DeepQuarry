#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Real automatic cliff shaping must copy ramp passability through the stat layer.
/datum/unit_test/dq_cliff_bottom_density/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/upper = get_step(get_step(test_floor(), NORTH), NORTH)
	var/turf/lower = get_step(upper, SOUTH)
	TEST_ASSERT(upper && lower, "The fixture needs two real adjacent floor turfs")
	for(var/cliff_type in list(/obj/structure/cliff/automatic, /obj/structure/cliff/automatic/ramp))
		var/obj/structure/cliff/C = allocate(cliff_type, upper)
		// Execute the existing after-init shape_cliff path, not a substitute builder.
		test_time(1 SECOND)
		test_drain()
		var/obj/structure/cliff/bottom/B = locate_on(lower, /obj/structure/cliff/bottom)
		TEST_ASSERT(B, "The actual automatic shape must create its lower ledge")
		own(B)
		TEST_ASSERT_EQUAL(get_turf(B), lower, "The lower ledge must occupy the tile south of its upper ledge")
		TEST_ASSERT(C.is_double_cliff && B.is_double_cliff, "Both real ledges must retain their two-tile geometry")
		TEST_ASSERT_EQUAL(B.dir, C.dir, "The lower ledge must preserve the actual upper direction")
		TEST_ASSERT_EQUAL(B.ramp, C.ramp, "The lower ledge must preserve ramp identity")
		TEST_ASSERT_EQUAL(B.density, !C.ramp, "Ramp bottoms stay passable while normal bottoms stay solid")
		TEST_ASSERT_EQUAL(stat_value(B, STAT_DENSITY), B.density, "The served density and native composed density must agree")
		TEST_ASSERT_EQUAL(stat_value(C, STAT_DENSITY), C.density, "The upper ledge must also retain stat parity")
		qdel(B)
		qdel(C)

#endif
