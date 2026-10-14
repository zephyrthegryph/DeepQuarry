#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A shadekin that dies mid-smite must not leave the victim stuck transforming.
/datum/unit_test/shadekin_smite_dies_mid_sequence/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/mob/living/simple_mob/shadekin/shadekin = allocate(/mob/living/simple_mob/shadekin/purple, T)
	target.set_transforming(TRUE)
	shadekin_smite_step(shadekin, target, null, 1)
	test_time(2 SECONDS)
	spent(shadekin)
	test_time(SHADEKIN_SMITE_RELEASE + 1 SECOND)
	TEST_ASSERT(!target.transforming, "the victim stayed transforming after the shadekin died mid-show")
	test_driver_end()

/// A drain beam whose victim is deleted ends by itself: its cleanup does not wait for the victim.
/datum/unit_test/ectoplasm_beam_victim_deleted/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/pen/origin = allocate(/obj/item/pen, T)
	var/obj/item/pen/victim = allocate(/obj/item/pen, get_step(T, EAST))
	var/datum/beam/beam = origin.Beam(victim, icon_state = "drain_life", time = 10 SECONDS)
	beam.Start()
	qdel(victim)
	beam.beam_tick()
	TEST_ASSERT(QDELETED(beam), "the drain beam outlived its deleted victim")
	test_driver_end()

#endif
