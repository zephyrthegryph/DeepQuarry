/// The actual spray-bottle entry emits its configured mixed dose into a real travelling puff and refuses a smaller remainder.
/datum/unit_test/interim_spray_bottle_mixed_dose
	parent_type = /datum/unit_test/dq_p2_reagents

/datum/unit_test/interim_spray_bottle_mixed_dose/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/target = run_loc_floor_top_right
	var/mob/living/carbon/human/user = rc_actor(T)
	var/obj/item/reagent_containers/spray/bottle = allocate(/obj/item/reagent_containers/spray, T)
	TEST_ASSERT(target != T && !target.density, "the actual spray target is a distinct open test-floor turf")
	var/turf/first_step = get_step(T, get_dir(T, target))
	TEST_ASSERT_NOTNULL(first_step, "the actual spray route has a first travel turf")
	TEST_ASSERT(!first_step.density && first_step != T, "the actual first travel turf is open and distinct from the actor origin")
	TEST_ASSERT_NULL(locate(/mob) in first_step, "the actual first travel turf has no mob that would receive the emitted dose immediately")
	TEST_ASSERT(user.put_in_active_hand(bottle), "the actor holds the real base spray bottle")
	TEST_ASSERT_EQUAL(bottle.amount_per_transfer_from_this, 10, "the actual base bottle has a ten-unit spray dose")
	bottle.reagents.add_reagent(REAGENT_ID_NUTRIMENT, 10)
	bottle.reagents.add_reagent(REAGENT_ID_SUGAR, 10)
	var/list/before = list()
	for(var/obj/effect/effect/water/chempuff/puff in range(1, T))
		before += puff
	TEST_ASSERT_EQUAL(length(before), 0, "the real spray origin starts without a travelling chemical puff")
	rc_click(user, target, bottle, I_HELP, FALSE)
	var/list/emitted = list()
	for(var/obj/effect/effect/water/chempuff/puff in range(1, T))
		own(puff)
		emitted += puff
	TEST_ASSERT_EQUAL(length(emitted), 1, "the actual spray entry emits exactly one travelling chemical puff")
	var/obj/effect/effect/water/chempuff/puff = emitted[1]
	TEST_ASSERT_NOTNULL(puff.reagents, "the actual emitted puff has its real reagent holder")
	TEST_ASSERT_EQUAL(puff.reagents.total_volume, 10, "the actual puff receives exactly the configured dose")
	TEST_ASSERT(abs(puff.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT) - 5) < 0.001, "the actual puff receives five units of original nutriment")
	TEST_ASSERT(abs(puff.reagents.get_reagent_amount(REAGENT_ID_SUGAR) - 5) < 0.001, "the actual puff receives five units of original sugar")
	TEST_ASSERT_EQUAL(bottle.reagents.total_volume, 10, "the actual spray debits exactly ten units from its source")
	TEST_ASSERT(abs(bottle.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT) - 5) < 0.001, "the actual source retains its five-unit nutriment remainder")
	TEST_ASSERT(abs(bottle.reagents.get_reagent_amount(REAGENT_ID_SUGAR) - 5) < 0.001, "the actual source retains its five-unit sugar remainder")
	TEST_ASSERT_EQUAL(user.get_active_hand(), bottle, "actual spraying preserves the original held bottle")
	// Keep the source's measured remainder, then lower it below the actual entry's minimum dose.
	bottle.reagents.remove_reagent(REAGENT_ID_SUGAR, 1)
	TEST_ASSERT_EQUAL(bottle.reagents.total_volume, 9, "the real source now contains a positive remainder below one dose")
	rc_click(user, target, bottle, I_HELP, FALSE)
	var/after_count = 0
	for(var/obj/effect/effect/water/chempuff/after_puff in range(1, T))
		own(after_puff)
		after_count++
	TEST_ASSERT_EQUAL(after_count, 1, "the undersized remainder produces no additional actual puff")
	TEST_ASSERT_EQUAL(bottle.reagents.total_volume, 9, "the undersized-dose refusal preserves every remaining source unit")
	TEST_ASSERT(abs(bottle.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT) - 5) < 0.001, "the refusal preserves all remaining nutriment")
	TEST_ASSERT(abs(bottle.reagents.get_reagent_amount(REAGENT_ID_SUGAR) - 4) < 0.001, "the refusal preserves all remaining sugar")
