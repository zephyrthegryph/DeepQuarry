#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_tanning_rack_tracks_leather_wetness/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/obj/structure/tanning_rack/rack = allocate(/obj/structure/tanning_rack, test_floor())
	var/obj/item/stack/wetleather/leather = allocate(/obj/item/stack/wetleather, rack)
	rel_set(rack, nameof(rack.drying), leather)
	test_drain()
	TEST_ASSERT(("leather_wet" in dq_overlay_states(rack)), "real wet leather draws the wet overlay on its rack")
	TEST_ASSERT(!("leather_dry" in dq_overlay_states(rack)), "the dry overlay is absent before the producer changes")
	leather.set_wetness(0)
	test_drain()
	TEST_ASSERT(("leather_dry" in dq_overlay_states(rack)), "the real leather setter redraws its rack without manual publication")
	TEST_ASSERT(!("leather_wet" in dq_overlay_states(rack)), "the previous wet overlay is removed")
	TEST_ASSERT_EQUAL(rack.drying(), leather, "redrawing preserves the real drying relation")
	test_driver_end()

#endif
