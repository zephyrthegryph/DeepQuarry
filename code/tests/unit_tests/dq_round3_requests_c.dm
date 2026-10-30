// Only client/window transport is supplied for this headless test actor. The real
// consciousness, incapacitation and containment-distance gates still run.
/mob/living/carbon/human/round3_request_actor/default_can_use_tgui_topic(src_object)
	if(stat)
		return STATUS_DISABLED
	if(incapacitated())
		return STATUS_UPDATE
	if(!loc)
		return STATUS_CLOSE
	return min(STATUS_INTERACTIVE, loc.contents_tgui_distance(src_object, src))

/datum/unit_test/dq_hc_computers/dq_round3_requests_c/proc/request_actor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/round3_request_actor, hc_side())
	H.enable_godmode()
	return H

// The real window operation chooses only the matching same-actor request step.
/datum/unit_test/dq_hc_computers/dq_round3_requests_c
	abstract_type = /datum/unit_test/dq_hc_computers/dq_round3_requests_c

/datum/unit_test/dq_hc_computers/dq_round3_requests_c/proc/petrification_machine()
	var/obj/machinery/petrification/C = allocate(/obj/machinery/petrification, hc_spot())
	C.set_grid_power(TRUE)
	C.set_broken_condition(FALSE)
	return C

/datum/unit_test/dq_hc_computers/dq_round3_requests_c/tint
/datum/unit_test/dq_hc_computers/dq_round3_requests_c/tint/run_gate()
	var/obj/machinery/petrification/C = petrification_machine()
	var/mob/living/carbon/human/H = request_actor()
	var/before = C.tint
	var/datum/op_result/result = test_ui(H, C, "set_option", list("option" = "tint"))
	TEST_ASSERT_EQUAL(result?.key, "set_option", "the actual window button resolves the native settings op")
	TEST_ASSERT_NULL(result?.outcome, "the color step suspends the original op")
	var/datum/prompt/color/statue_tint/P = SSrequests.open_for(H)
	TEST_ASSERT(istype(P), "the real color request is opened for the actual operator")
	TEST_ASSERT_EQUAL(P.step_name, "tint", "the matching step is named tint")
	TEST_ASSERT_EQUAL(P.default, before, "the request snapshots the current tint")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the unrelated text step opens no question")
	test_answer(H, "#123456")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "answering resumes and commits the original settings op")
	TEST_ASSERT_EQUAL(C.tint, "#123456", "the actual machine receives the chosen color")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "the op leaves no question pending")

/datum/unit_test/dq_hc_computers/dq_round3_requests_c/adjective
/datum/unit_test/dq_hc_computers/dq_round3_requests_c/adjective/run_gate()
	var/obj/machinery/petrification/C = petrification_machine()
	var/mob/living/carbon/human/H = request_actor()
	var/before = C.adjective
	var/datum/op_result/result = test_ui(H, C, "set_option", list("option" = "adjective"))
	TEST_ASSERT_EQUAL(result?.key, "set_option", "the actual text button resolves the native settings op")
	TEST_ASSERT_NULL(result?.outcome, "the text step suspends the original op")
	var/datum/prompt/text/statue_option/P = SSrequests.open_for(H)
	TEST_ASSERT(istype(P), "the production text subtype supplies its normalization")
	TEST_ASSERT_EQUAL(P.option, "adjective", "the request captures which actual option is being edited")
	TEST_ASSERT_EQUAL(P.default, before, "the current option is the displayed default")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the unrelated tint step opens no question")
	test_answer(H, "polish")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "the text answer resumes the actual op")
	TEST_ASSERT_EQUAL(C.adjective, "polishes", "the existing conjugation behavior survives the request conversion")

/datum/unit_test/dq_hc_computers/dq_round3_requests_c/cancel
/datum/unit_test/dq_hc_computers/dq_round3_requests_c/cancel/run_gate()
	var/obj/machinery/petrification/C = petrification_machine()
	var/mob/living/carbon/human/H = request_actor()
	var/before = C.material
	var/datum/op_result/result = test_ui(H, C, "set_option", list("option" = "material"))
	TEST_ASSERT_EQUAL(result?.key, "set_option", "cancellation starts from the actual settings button")
	TEST_ASSERT(SSrequests.open_for(H), "a real question exists before cancellation")
	test_answer(H, null, outcome = REQ_CANCELLED)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "cancellation terminates the original pending op")
	TEST_ASSERT_EQUAL(C.material, before, "canceling preserves the actual machine material")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "canceling leaves no actor request")

/datum/unit_test/dq_hc_computers/dq_round3_requests_c/toggle
/datum/unit_test/dq_hc_computers/dq_round3_requests_c/toggle/run_gate()
	var/obj/machinery/petrification/C = petrification_machine()
	var/mob/living/carbon/human/H = request_actor()
	var/before = C.discard_clothes
	var/datum/op_result/result = test_ui(H, C, "set_option", list("option" = "discard_clothes"))
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "the real toggle commits without an answer")
	TEST_ASSERT_EQUAL(C.discard_clothes, !before, "the actual toggle state changes")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "neither conditional request runs for a toggle")

/datum/unit_test/dq_hc_computers/dq_round3_requests_c/target_guard
/datum/unit_test/dq_hc_computers/dq_round3_requests_c/target_guard/run_gate()
	var/obj/machinery/petrification/C = petrification_machine()
	var/mob/living/carbon/human/H = request_actor()
	TEST_ASSERT(!C.is_valid_target(H), "the real headless human cannot be made a consent-capable target")
	var/datum/op_result/result = test_ui(H, C, "set_option", list("option" = "target"))
	TEST_ASSERT_EQUAL(result?.key, "set_option", "the native window dispatch starts the real target selection")
	var/datum/prompt/choice/statue_target/P = SSrequests.open_for(H)
	TEST_ASSERT(istype(P), "the actual operator receives the production target picker")
	var/selected
	for(var/key in P.choices)
		if(P.choices[key] == H)
			selected = key
	TEST_ASSERT(selected, "the real target scan contains the actual nearby human")
	TEST_ASSERT_NULL(P.step_name, "the unchanged standalone picker retains its separate cross-actor consent workflow")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "unrelated tint and text questions remain skipped")
	test_answer(H, selected)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "the operator's valid choice resumes its original op")
	TEST_ASSERT_NULL(C.target_ref(), "the unchanged live-client target guard prevents an invalid assignment")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "an invalid target is never asked for consent")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "the finished picker leaves no actor request")
