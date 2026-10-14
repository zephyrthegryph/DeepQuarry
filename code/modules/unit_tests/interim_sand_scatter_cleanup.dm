/// Actual thrown sand blinds a real eyed human and scatters on its original deadline only while still on a floor.
/datum/unit_test/om/interim_sand_scatter_cleanup
	var/pick_up_before_deadline = FALSE

/datum/unit_test/om/interim_sand_scatter_cleanup/picked_up
	pick_up_before_deadline = TRUE

/datum/unit_test/om/interim_sand_scatter_cleanup/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/ore/glass/sand = allocate(/obj/item/ore/glass, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(victim.has_eyes(), "The actual sand impact victim has real eyes")
	TEST_ASSERT(!victim.has_status(STAT_BLINDED), "The actual eyed victim starts without the sand's blindness effect")
	// Real impacts retain their original chance; the fixed seed makes this bounded sequence repeatable.
	rand_seed(22156)
	for(var/attempt = 1, attempt <= 10 && !victim.has_status(STAT_BLINDED), attempt++)
		sand.throw_impact(victim)
	TEST_ASSERT(victim.has_status(STAT_BLINDED), "The fixed-seed actual sand throw impact applies its real blindness status")
	TEST_ASSERT(victim.has_status(STAT_BLURRY), "The actual sand throw impact also applies its original real blurred-vision status")
	TEST_ASSERT(!QDELETED(sand) && sand.loc == T, "Actual sand impact retains the exact original floor source before its delayed scatter")
	if(pick_up_before_deadline)
		TEST_ASSERT(actor.put_in_active_hand(sand), "The actual actor picks up the original impacted sand before its scatter deadline")
		TEST_ASSERT_EQUAL(sand.loc, actor, "The real pickup places the exact original source into the actor")
	scheduler_advance((0.05 SECONDS) / (1 SECOND))
	TEST_ASSERT(!QDELETED(sand), "The exact original sand survives before its original tenth-second scatter deadline")
	scheduler_advance((0.15 SECONDS) / (1 SECOND))
	if(pick_up_before_deadline)
		TEST_ASSERT(!QDELETED(sand), "The actual delayed callback preserves the original source picked up before its deadline")
		TEST_ASSERT_EQUAL(actor.get_active_hand(), sand, "Actual floor-only scatter refusal preserves the exact original held sand")
		TEST_ASSERT_EQUAL(sand.loc, actor, "Actual floor-only scatter refusal preserves the original actor containment")
	else
		TEST_ASSERT(QDELETED(sand), "The actual delayed scatter consumes the exact original sand left on its floor")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual sand scattering preserves the exact unrelated original floor pen")
	TEST_ASSERT(!QDELETED(victim) && victim.loc == T, "Actual delayed sand scattering preserves the original impacted victim and floor")
