/// Real window input and answers exercise the conditional workflow, including cancellation.
/datum/unit_test/dq_fwg3_ui/round3_petrification_questions

/datum/unit_test/dq_fwg3_ui/round3_petrification_questions/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/petrification/M = allocate(/obj/machinery/petrification, T)
	M.set_grid_power(TRUE)
	M.set_broken_condition(FALSE)
	var/original_tint = M.tint
	test_ui(H, M, "set_option", list("option" = "tint"))
	var/datum/prompt/color/statue_tint/color_question = SSrequests.open_for(H)
	TEST_ASSERT(istype(color_question), "Tint uses the original typed color question")
	TEST_ASSERT_EQUAL(color_question?.title, "Statue color", "The question retains its title")
	TEST_ASSERT_EQUAL(color_question?.default, original_tint, "The question starts with the current tint")
	TEST_ASSERT_EQUAL(M.tint, original_tint, "Opening the question does not change the machine")
	test_answer(H, "#112233")
	TEST_ASSERT_EQUAL(M.tint, "#112233", "Answering commits the chosen tint")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "The unrelated text step is skipped")
	test_ui(H, M, "set_option", list("option" = "adjective"))
	var/datum/prompt/text/statue_option/text_question = SSrequests.open_for(H)
	TEST_ASSERT(istype(text_question), "An adjective uses the original typed text question")
	TEST_ASSERT_EQUAL(text_question?.option, "adjective", "The question captures the selected setting")
	test_answer(H, "shimmer")
	TEST_ASSERT_EQUAL(M.adjective, "shimmers", "The existing adjective normalization is retained")
	var/original_identifier = M.identifier
	test_ui(H, M, "set_option", list("option" = "identifier"))
	test_answer(H, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(M.identifier, original_identifier, "Cancellation cannot change the setting")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "Cancellation closes the pending workflow")
	var/original_discard = M.discard_clothes
	test_ui(H, M, "set_option", list("option" = "discard_clothes"))
	TEST_ASSERT_EQUAL(M.discard_clothes, !original_discard, "A toggle remains immediate")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "A toggle asks neither conditional question")
