/// Genuine RMS choices preserve material costs and dropped-adjacent late answers.
/datum/unit_test/round2_rms_material_choice_native
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_rms_material_choice_native/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/obj/item/rms/synthesizer = allocate(/obj/item/rms, T)
	TEST_ASSERT_EQUAL(synthesizer.mode_index, 1, "actual RMS constructor starts in Steel mode")
	TEST_ASSERT_EQUAL(synthesizer.charge_cost_basic, 1000, "actual constructor preserves basic material cost")
	TEST_ASSERT_EQUAL(synthesizer.charge_cost_random, 3333, "actual constructor preserves random material cost")
	TEST_ASSERT(user.put_in_active_hand(synthesizer), "actual actor holds original synthesizer")
	// Seed an existing Random configuration so every accepted choice must change actual state.
	synthesizer.set_mode_index(6)
	synthesizer.set_charge_cost(synthesizer.charge_cost_random)
	var/list/expected_modes = list("Steel" = 1, "Glass" = 2, "Cloth" = 3, "Plastic" = 4, "Stone" = 5, "Random" = 6)
	var/starting_charge = synthesizer.stored_charge
	var/completed = 0
	for(var/material in expected_modes)
		TEST_ASSERT(!user.incapacitated(), "actual actor remains capable before real request")
		TEST_ASSERT(synthesizer.mode_index != expected_modes[material], "each accepted choice must change the actual existing mode")
		test_click(user, synthesizer, synthesizer)
		test_time(1 SECOND)
		var/datum/prompt/choice/request = SSrequests.open_for(user)
		TEST_ASSERT(istype(request), "actual held click opens native RMS choice")
		TEST_ASSERT(request.radial && request.tooltips, "actual request preserves radial tooltips")
		TEST_ASSERT_EQUAL(request.anchor, synthesizer, "actual menu anchor is original synthesizer")
		TEST_ASSERT_EQUAL(request.timeout, REQUEST_DEFAULT_TIMEOUT, "actual choice retains unlimited timeout (a request given no timeout gets the default, framework_gaps.md E2)")
		TEST_ASSERT_EQUAL(length(request.choices), 6, "actual menu offers exactly six material choices")
		TEST_ASSERT(material in request.choices, "actual native request offers the canonical material")
		if(material == "Random")
			TEST_ASSERT(user.unEquip(synthesizer), "actor genuinely drops original device while choice is open")
			TEST_ASSERT_EQUAL(synthesizer.loc, T, "original dropped device stays on exact fixture floor")
			TEST_ASSERT(user.Adjacent(synthesizer), "actual dropped device remains adjacent")
		test_answer(user, material)
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(synthesizer.mode_index, expected_modes[material], "actual accepted answer sets exact requested material mode")
		TEST_ASSERT_EQUAL(synthesizer.charge_cost, material == "Random" ? 3333 : 1000, "actual accepted answer sets exact original material cost")
		TEST_ASSERT_EQUAL(synthesizer.stored_charge, starting_charge, "actual mode selection consumes no stored charge")
		TEST_ASSERT_NULL(SSrequests.open_for(user), "actual accepted request closes")
		TEST_ASSERT(!QDELETED(synthesizer), "actual choice preserves original item identity")
		if(material == "Random")
			TEST_ASSERT_EQUAL(synthesizer.loc, T, "dropped-adjacent answer leaves original item on original floor")
		else
			TEST_ASSERT_EQUAL(user.get_active_hand(), synthesizer, "held choice preserves exact source hand")
		completed++
	TEST_ASSERT_EQUAL(completed, 6, "all six genuine material choices completed")
