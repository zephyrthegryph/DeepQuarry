// An actor has any number of pending ops (doc/rewrite/final_api.html, section 9, "Interruption and flows"): waiting on an answer is never exclusive, and
// what conflicts is claims() (the actor's hands and body, an exclusive target). Each question is its own window bound to its own op and closes on its
// own loss; asking the same thing again focuses the window that is open; an actor holds at most OP_PENDING_CAP, and every cancellation says why.

/// Two panels of an admin tool: each topic op asks its own question.
/datum/dq_multi_panel
	var/n = 0
	var/m = 0

CAPABILITIES(/datum/dq_multi_panel)
	op("ask_n", topic("ask_n"), asks(/datum/prompt/number, fields = list("question" = "N?", "timeout" = 0), step = "n"), then(PROC_REF(set_n)))
	op("ask_m", topic("ask_m"), asks(/datum/prompt/number, fields = list("question" = "M?", "timeout" = 0), step = "m"), then(PROC_REF(set_m)))

/datum/dq_multi_panel/proc/set_n(datum/act/op/A)
	n = A.step_value("n")
	return OP_OK

/datum/dq_multi_panel/proc/set_m(datum/act/op/A)
	m = A.step_value("m")
	return OP_OK

/datum/unit_test/dq_prompt_interrupt/two_questions_coexist
/datum/unit_test/dq_prompt_interrupt/two_questions_coexist/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B1 = make_box()
	var/obj/e0_fixture/prompt_base/B2 = make_box()
	test_click(H, B1)
	test_click(H, B2)
	var/list/pendings = op_pendings_of(H)
	TEST_ASSERT_EQUAL(length(pendings), 2, "both questions are pending: the second input did not cancel the first")
	var/datum/pending_op/first = pendings[1]
	var/datum/pending_op/second = pendings[2]
	TEST_ASSERT(first.request?.is_open() && second.request?.is_open(), "and both prompts are open")
	TEST_ASSERT_NULL(test_prompt_answer(second.request, 5), "the newer one is answered first")
	TEST_ASSERT_EQUAL(B2.value, 5, "its answer reached its own machine")
	TEST_ASSERT_EQUAL(B1.runs, 0, "the other is untouched")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "and still waits")
	TEST_ASSERT_NULL(test_prompt_answer(first.request, 8), "then the older is answered")
	TEST_ASSERT_EQUAL(B1.value, 8, "its answer reached its own machine")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "nothing is pending")

/datum/unit_test/dq_prompt_interrupt/answering_by_op_key_picks_the_question
/datum/unit_test/dq_prompt_interrupt/answering_by_op_key_picks_the_question/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	var/datum/dq_multi_panel/panel = new
	test_click(H, B)
	inbox_topic(H, panel, list("ask_n" = 1))
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "a window question beside a click's")
	test_answer(H, 4, op_key = "ask_n")
	TEST_ASSERT_EQUAL(panel.n, 4, "the answer went to the op named")
	TEST_ASSERT_EQUAL(B.runs, 0, "not to the older one")
	test_answer(H, 6)
	TEST_ASSERT_EQUAL(B.value, 6, "which the plain form answers next")

/datum/unit_test/dq_prompt_interrupt/a_question_and_a_physical_wait_coexist
/datum/unit_test/dq_prompt_interrupt/a_question_and_a_physical_wait_coexist/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	var/obj/e0_fixture/prompt_base/lever/L = make_box(/obj/e0_fixture/prompt_base/lever)
	test_click(H, B)
	var/datum/op_result/working = test_click(H, L)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "the question stays open while the actor works")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(working?.outcome, ACT_COMMITTED, "the work finished")
	TEST_ASSERT_EQUAL(L.runs, 1, "and ran")
	TEST_ASSERT_NOTNULL(op_pending_for(H, "set"), "the question is still waiting for its answer")
	test_answer(H, 3)
	TEST_ASSERT_EQUAL(B.value, 3, "and is answered")

/datum/unit_test/dq_prompt_interrupt/a_physical_wait_does_not_stop_a_question_started_after_it
/datum/unit_test/dq_prompt_interrupt/a_physical_wait_does_not_stop_a_question_started_after_it/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/lever/L = make_box(/obj/e0_fixture/prompt_base/lever)
	var/datum/dq_multi_panel/panel = new
	var/datum/op_result/working = test_click(H, L)
	inbox_topic(H, panel, list("ask_n" = 1))
	TEST_ASSERT_NULL(working?.outcome, "a window question does not need the hands: the work goes on")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "both are pending")

/datum/unit_test/dq_prompt_interrupt/two_physical_waits_conflict
/datum/unit_test/dq_prompt_interrupt/two_physical_waits_conflict/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	var/obj/e0_fixture/prompt_base/lever/L1 = make_box(/obj/e0_fixture/prompt_base/lever)
	var/obj/e0_fixture/prompt_base/lever/L2 = make_box(/obj/e0_fixture/prompt_base/lever)
	test_click(H, B)
	var/datum/op_result/first = test_click(H, L1)
	var/datum/op_result/second = test_click(H, L2)
	TEST_ASSERT_EQUAL(first?.outcome, ACT_REFUSED, "the second physical action stopped the first")
	TEST_ASSERT_EQUAL(first?.reason, /datum/msg/op/stopped, "and the actor is told why")
	TEST_ASSERT_NULL(second?.outcome, "the second is under way")
	TEST_ASSERT_NOTNULL(op_pending_for(H, "set"), "the question was not part of the conflict")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "the question and the new work are pending")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(L1.runs, 0, "the stopped work never ran")
	TEST_ASSERT_EQUAL(L2.runs, 1, "the second did")

/datum/unit_test/dq_prompt_interrupt/an_ai_during_physical_work_is_refused
/datum/unit_test/dq_prompt_interrupt/an_ai_during_physical_work_is_refused/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/lever/L1 = make_box(/obj/e0_fixture/prompt_base/lever)
	var/obj/e0_fixture/prompt_base/lever/L2 = make_box(/obj/e0_fixture/prompt_base/lever)
	var/datum/op_result/first = test_click(H, L1)
	var/datum/op_result/refused = perform_op(H, L2, "work", origin = ORIGIN_AI)
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/op/busy, "an AI's second physical action is refused as busy")
	TEST_ASSERT_NULL(first?.outcome, "and does not stop the work")

/datum/unit_test/dq_prompt_interrupt/work_then_question_holds_hands_through_the_question
/datum/unit_test/dq_prompt_interrupt/work_then_question_holds_hands_through_the_question/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/work_then_ask/W = make_box(/obj/e0_fixture/prompt_base/work_then_ask)
	var/obj/e0_fixture/prompt_base/lever/L = make_box(/obj/e0_fixture/prompt_base/lever)
	test_click(H, W)
	test_time(2 SECONDS)
	TEST_ASSERT_NOTNULL(op_pending_for(H, "work_ask")?.request, "the work is done and the op asks")
	var/datum/op_result/other = test_click(H, L)
	TEST_ASSERT_NULL(op_pending_for(H, "work_ask"), "an open question holds the op's claims: a player's other work stops it")
	TEST_ASSERT_NULL(other?.outcome, "the other work started")

/datum/unit_test/dq_prompt_interrupt/claims_that_do_not_overlap_coexist
/datum/unit_test/dq_prompt_interrupt/claims_that_do_not_overlap_coexist/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/holder/D = make_box(/obj/e0_fixture/prompt_base/holder)
	var/obj/e0_fixture/prompt_base/lever/L = make_box(/obj/e0_fixture/prompt_base/lever)
	var/datum/op_result/held = test_click(H, D)
	var/datum/op_result/other = test_click(H, L)
	TEST_ASSERT_NULL(held?.outcome, "claims(CLAIM_TARGET) holds the thing, not the actor's hands: it goes on")
	TEST_ASSERT_NULL(other?.outcome, "and so does the other work")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "both are pending")
	// the target claim still refuses a second claimant
	var/mob/living/carbon/human/H2 = make_person()
	var/datum/op_result/refused = test_click(H2, D)
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/op/claimed, "a second actor on the claimed target is refused")

/datum/unit_test/dq_prompt_interrupt/each_window_closes_on_its_own_loss
/datum/unit_test/dq_prompt_interrupt/each_window_closes_on_its_own_loss/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B1 = make_box()
	var/obj/e0_fixture/prompt_base/B2 = make_box()
	test_click(H, B1)
	test_click(H, B2)
	var/datum/pending_op/first = op_pendings_of(H)[1]
	var/datum/pending_op/second = op_pendings_of(H)[2]
	var/datum/request/first_request = first.request
	var/datum/request/second_request = second.request
	B1.set_powered(FALSE)
	test_time(1)
	TEST_ASSERT(!first_request.is_open(), "the machine that lost power closed its own prompt")
	TEST_ASSERT(second_request.is_open(), "the other prompt is untouched")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "one op is left")
	qdel(B2)
	test_time(1)
	TEST_ASSERT(!second_request.is_open(), "deleting the other target closed the other prompt")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "nothing is left")

/datum/unit_test/dq_prompt_interrupt/walking_away_closes_every_open_question
/datum/unit_test/dq_prompt_interrupt/walking_away_closes_every_open_question/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B1 = make_box()
	var/obj/e0_fixture/prompt_base/B2 = make_box(/obj/e0_fixture/prompt_base/keeps)
	test_click(H, B1)
	test_click(H, B2)
	H.forceMove(far_away())
	test_time(1)
	TEST_ASSERT_NULL(op_pending_for(H, "set"), "the question that keeps the actor near closed")
	TEST_ASSERT_NOTNULL(op_pending_for(H, "set_keeps"), "the one that opted out stays open")

/datum/unit_test/dq_prompt_interrupt/the_same_click_focuses_the_open_prompt
/datum/unit_test/dq_prompt_interrupt/the_same_click_focuses_the_open_prompt/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	var/obj/e0_fixture/prompt_base/B2 = make_box()
	test_click(H, B)
	var/datum/pending_op/P = op_pending_of(H)
	var/datum/prompt/asked = P.request
	test_click(H, B)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "clicking the same thing again opens no second prompt")
	TEST_ASSERT_EQUAL(op_pending_of(H), P, "the op is the same one")
	TEST_ASSERT_EQUAL(P.request, asked, "and so is its question")
	TEST_ASSERT_EQUAL(asked.focused, 1, "its window was focused")
	test_click(H, B2)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "another target is its own question")
	TEST_ASSERT_EQUAL(asked.focused, 1, "and did not focus the first")

/datum/unit_test/dq_prompt_interrupt/the_pending_cap_refuses_with_a_message
/datum/unit_test/dq_prompt_interrupt/the_pending_cap_refuses_with_a_message/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/list/boxes = list()
	for(var/i in 1 to OP_PENDING_CAP)
		var/obj/e0_fixture/prompt_base/B = make_box()
		boxes += B
		test_click(H, B)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), OP_PENDING_CAP, "the actor holds the cap")
	var/obj/e0_fixture/prompt_base/extra = make_box()
	var/datum/op_result/refused = test_click(H, extra)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "one more is refused")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/op/too_many_pending, "with a message")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), OP_PENDING_CAP, "and nothing was cancelled to make room")
	test_answer(H, 1)
	var/datum/op_result/accepted = test_click(H, extra)
	TEST_ASSERT_NULL(accepted?.outcome, "once one is answered there is room again")

/datum/unit_test/dq_prompt_interrupt/two_admin_panels_ask_at_once
/datum/unit_test/dq_prompt_interrupt/two_admin_panels_ask_at_once/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/datum/dq_multi_panel/first = new
	var/datum/dq_multi_panel/second = new
	inbox_topic(H, first, list("ask_n" = 1))
	inbox_topic(H, second, list("ask_n" = 1))
	inbox_topic(H, first, list("ask_m" = 1))
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 3, "three questions from two panels are open at once")
	inbox_topic(H, first, list("ask_n" = 1))
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 3, "pressing a panel's open button again opens no duplicate")
	var/datum/pending_op/p1 = op_pendings_of(H)[1]
	var/datum/pending_op/p2 = op_pendings_of(H)[2]
	var/datum/pending_op/p3 = op_pendings_of(H)[3]
	TEST_ASSERT_NULL(test_prompt_answer(p3.request, 3), "the third is answered first")
	TEST_ASSERT_EQUAL(first.m, 3, "to the panel that asked")
	TEST_ASSERT_NULL(test_prompt_answer(p1.request, 1), "then the first")
	TEST_ASSERT_EQUAL(first.n, 1, "to its panel")
	TEST_ASSERT_EQUAL(second.n, 0, "the other panel's question is still open")
	TEST_ASSERT_NULL(test_prompt_answer(p2.request, 2), "and answers last")
	TEST_ASSERT_EQUAL(second.n, 2, "to its own panel")

/datum/unit_test/dq_prompt_interrupt/a_deleted_panel_closes_only_its_question
/datum/unit_test/dq_prompt_interrupt/a_deleted_panel_closes_only_its_question/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/datum/dq_multi_panel/first = new
	var/datum/dq_multi_panel/second = new
	inbox_topic(H, first, list("ask_n" = 1))
	inbox_topic(H, second, list("ask_n" = 1))
	qdel(first)
	test_time(1)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "closing a panel closes its question")
	TEST_ASSERT_NOTNULL(op_pendings_of(H)[1], "the other panel's stays")
