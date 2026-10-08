// The registry catalogue is prepared by the actual request, outside pure menu admission.
/datum/unit_test/dq_hc_computers/round2_borgupload_empty_selection

/datum/unit_test/dq_hc_computers/round2_borgupload_empty_selection/run_gate()
	var/obj/machinery/computer/borgupload/C = hc_console(/obj/machinery/computer/borgupload)
	var/mob/living/carbon/human/H = hc_actor()
	TEST_ASSERT_EQUAL(length(free_borg_choices()), 0, "the actual focused-world borg catalogue is empty")
	TEST_ASSERT_NULL(C.current(), "the real console begins without a selected cyborg")
	var/list/menu = op_menu(H, C, null)
	var/list/selection_row
	for(var/list/row as anything in menu)
		if(row["key"] == "select_borg")
			selection_row = row
	TEST_ASSERT(selection_row, "the real menu includes the actual native selection operation")
	TEST_ASSERT(selection_row["enabled"], "power and integrity allow admission before the request queries its catalogue")
	var/prompts_before = length(GLOB.test_prompts)
	var/datum/op_result/result = test_click(H, C, null)
	TEST_ASSERT_EQUAL(result?.key, "select_borg", "the real public hand click dispatches the selection operation")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the actual opening catalogue rejection refuses the pending selection")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/op/answer_no, "an opening recheck cancellation uses the request engine's precise cancellation result")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), prompts_before + 1, "the actual native selection attempted exactly one request")
	var/datum/prompt/choice/borg_upload_selection/question = GLOB.test_prompts[length(GLOB.test_prompts)]
	TEST_ASSERT(istype(question), "the attempted question is the production borg-selection subtype")
	TEST_ASSERT_EQUAL(length(question.choices), 0, "the actual request prepared the real empty catalogue")
	TEST_ASSERT_EQUAL(question.recheck_extra(), "no free cyborgs detected", "the request owns the exact availability refusal")
	TEST_ASSERT_NULL(question.window, "opening availability rejection never displayed a selection window")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "the real actor has no pending selection question")
	TEST_ASSERT_NULL(C.current(), "opening rejection leaves the actual selected cyborg unchanged")

// A production request may answer during opening, before request_open() returns.
/datum/prompt/choice/round2_sync_answer
	choices = list("first")
	timeout = REQUEST_NO_TIMEOUT

/datum/prompt/choice/round2_sync_answer/begin()
	request_end(src, REQ_ANSWERED, "first")

/obj/round2_sync_ask_fixture
	var/first_value
	var/second_value
	var/effects = 0

CAPABILITIES(/obj/round2_sync_ask_fixture)
	op("chain", hand(), label("Chain"),
		asks(/datum/prompt/choice/round2_sync_answer, step = "first"),
		asks(/datum/prompt/choice, fields = list("choices" = list("second"), "timeout" = REQUEST_NO_TIMEOUT), step = "second"),
		then(PROC_REF(record_answers)))

/obj/round2_sync_ask_fixture/proc/record_answers(datum/act/op/A)
	first_value = A.step_value("first")
	second_value = A.step_value("second")
	effects++
	return OP_OK

/datum/unit_test/dq_hc_computers/round2_sync_answer_chain
/datum/unit_test/dq_hc_computers/round2_sync_answer_chain/run_gate()
	var/obj/round2_sync_ask_fixture/subject = allocate(/obj/round2_sync_ask_fixture, hc_spot())
	var/mob/living/carbon/human/H = hc_actor()
	var/datum/op_result/result = test_click(H, subject, null)
	TEST_ASSERT_EQUAL(result?.key, "chain", "the actual input starts the native chained operation")
	TEST_ASSERT_NULL(result?.outcome, "a synchronous first answer preserves the second pending question")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "the real operation opens exactly its two declared questions")
	var/datum/prompt/first = GLOB.test_prompts[1]
	TEST_ASSERT(QDELETED(first), "the original synchronous question is retired")
	var/datum/prompt/second = SSrequests.open_for(H)
	TEST_ASSERT(second, "the actual second request remains open")
	TEST_ASSERT_EQUAL(second.step_name, "second", "the surviving request has its declared step name")
	TEST_ASSERT_EQUAL(subject.effects, 0, "no effect runs before the second answer")
	test_answer(H, "second")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "the second real answer commits the original operation")
	TEST_ASSERT_EQUAL(subject.first_value, "first", "the synchronous answer retained its exact named step")
	TEST_ASSERT_EQUAL(subject.second_value, "second", "the later answer retained its exact named step")
	TEST_ASSERT_EQUAL(subject.effects, 1, "the chained operation applies its real effect exactly once")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "completion leaves no actor question open")
