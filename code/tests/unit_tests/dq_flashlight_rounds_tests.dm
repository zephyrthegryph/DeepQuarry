// The item round active_play times (pick up, use in hand twice, drop), several rounds in one tick: each use switches the light.

/datum/unit_test/dq_flashlight_rounds_toggle

/datum/unit_test/dq_flashlight_rounds_toggle/Run()
	var/turf/floor = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, floor)
	H.mind_initialize() // as active_play makes its crew
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, floor)
	var/switched = 0
	var/uses = 0
	for(var/round in 1 to 3)
		if(F.loc != H.loc)
			F.forceMove(H.loc)
		TEST_ASSERT(H.put_in_hands(F), "round [round]: the human takes the light")
		TEST_ASSERT_EQUAL(F.loc, H, "round [round]: the light is in a hand")
		for(var/use in 1 to 2)
			var/was_on = F.on
			var/why = flashlight_switch_refusal(F, H)
			F.attack_self(H)
			uses++
			if(F.on != was_on)
				switched++
			else
				log_world("dq_flashlight_rounds_toggle: round [round] use [use] did not switch (refusal: [why || "none"], cooldown: [!H.checkClickCooldown()], cell: [F.cell ? F.cell.charge : "none"])")
		H.drop_from_inventory(F, H.loc)
	TEST_ASSERT_EQUAL(switched, uses, "every use in hand switched the light")
