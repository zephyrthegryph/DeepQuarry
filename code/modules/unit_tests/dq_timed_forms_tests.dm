// The timed-action forms of the engine (doc/rewrite/final_api.html section 9): starts(), plays(at_start), msg_text(), asks(ends_on_no), captures() on a
// wait, claims() as the only exclusivity, ORIGIN_SYSTEM pendings, hold_busy() and every_running(). Fixtures: code/tests/engine/timed_forms_fixtures.dm.

/datum/unit_test/dq_timed_forms
	abstract_type = /datum/unit_test/dq_timed_forms

/datum/unit_test/dq_timed_forms/Run()
	test_driver_begin()
	run_forms()
	test_driver_end()

/datum/unit_test/dq_timed_forms/proc/run_forms()
	return

/datum/unit_test/dq_timed_forms/proc/person()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/datum/unit_test/dq_timed_forms/proc/site()
	return allocate(/obj/tf_site, run_loc_floor_bottom_left)

/datum/unit_test/dq_timed_forms/proc/said(mob/user, needle)
	for(var/line in test_chat_of(user))
		if(findtext(line, needle))
			return TRUE
	return FALSE

/datum/unit_test/dq_timed_forms/starts_runs_when_the_wait_starts
/datum/unit_test/dq_timed_forms/starts_runs_when_the_wait_starts/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_chat_clear()
	test_menu(H, S, "start")
	TEST_ASSERT_EQUAL(S.started, 1, "starts() ran as the wait began")
	TEST_ASSERT(said(H, "You begin the long work"), "and begins() said its line then")
	TEST_ASSERT_EQUAL(S.done, 0, "the effects wait")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "the effects ran at the end")
	TEST_ASSERT_EQUAL(S.started, 1, "starts() ran once")

/datum/unit_test/dq_timed_forms/begins_can_say_a_line_built_at_run_time
/datum/unit_test/dq_timed_forms/begins_can_say_a_line_built_at_run_time/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_chat_clear()
	test_menu(H, S, "dyn")
	TEST_ASSERT(said(H, "You heft the timed forms site for [H.name] to see."), "a handler returned msg_text() and the actor was told it")

/datum/unit_test/dq_timed_forms/a_second_input_does_not_cancel_the_first_wait
/datum/unit_test/dq_timed_forms/a_second_input_does_not_cancel_the_first_wait/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "free")
	test_menu(H, S, "free")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "two waits of one actor are pending: nothing stopped the first")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 2, "both finished")

/datum/unit_test/dq_timed_forms/only_overlapping_claims_conflict
/datum/unit_test/dq_timed_forms/only_overlapping_claims_conflict/run_forms()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "claimer")
	test_menu(H, S, "free")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 2, "an op that claims nothing coexists with a claiming one")
	test_menu(other, S, "claimer")
	TEST_ASSERT_EQUAL(length(op_pendings_of(other)), 0, "a second claim on the same target is refused")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 2, "the two coexisting ops finished")

/datum/unit_test/dq_timed_forms/asks_ends_the_op_on_no
/datum/unit_test/dq_timed_forms/asks_ends_the_op_on_no/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "ask")
	test_answer(H, FALSE)
	TEST_ASSERT_EQUAL(S.done, 0, "a no ends the op")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "and nothing is pending")
	test_menu(H, S, "ask")
	test_answer(H, TRUE)
	TEST_ASSERT_EQUAL(S.done, 1, "a yes goes on")

/datum/unit_test/dq_timed_forms/captures_work_on_a_wait
/datum/unit_test/dq_timed_forms/captures_work_on_a_wait/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "cap")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "an unchanged field lets the op finish")
	test_menu(H, S, "cap")
	S.set_amount(2)
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "a captured field that changed during the wait ended the op")

/datum/unit_test/dq_timed_forms/system_origin_waits_register_pendings
/datum/unit_test/dq_timed_forms/system_origin_waits_register_pendings/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	perform_op(H, S, "sys", null, ORIGIN_SYSTEM, AUTH_AI)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "the actor has the pending op")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "and it finished")

/datum/unit_test/dq_timed_forms/hold_busy_holds_and_calls_back
/datum/unit_test/dq_timed_forms/hold_busy_holds_and_calls_back/run_forms()
	var/obj/tf_site/S = site()
	TEST_ASSERT(!work_busy(S), "a site starts free")
	TEST_ASSERT_EQUAL(hold_busy(S, 2 SECONDS, TYPE_PROC_REF(/obj/tf_site, hold_ended)), TRUE, "it can be held")
	TEST_ASSERT(work_busy(S), "and is busy")
	TEST_ASSERT(istext(hold_busy(S, 2 SECONDS)), "a second hold is refused with a reason")
	test_time(3 SECONDS)
	TEST_ASSERT(!work_busy(S), "the hold runs out")
	TEST_ASSERT_EQUAL(S.ended, 1, "and calls back once")
	hold_busy(S, 10 SECONDS, TYPE_PROC_REF(/obj/tf_site, hold_ended))
	TEST_ASSERT(release_busy(S, TYPE_PROC_REF(/obj/tf_site, hold_ended)), "an early release is reported")
	TEST_ASSERT(!work_busy(S), "free again")
	TEST_ASSERT_EQUAL(S.ended, 2, "and the callback ran")
	test_time(11 SECONDS)
	TEST_ASSERT_EQUAL(S.ended, 2, "the cancelled timer did not call back again")

/datum/unit_test/dq_timed_forms/every_running_reads_the_armed_state
/datum/unit_test/dq_timed_forms/every_running_reads_the_armed_state/run_forms()
	var/obj/gap_every/E = allocate(/obj/gap_every, run_loc_floor_bottom_left)
	TEST_ASSERT(!every_running(E), "an every() parked behind its tracked var is not running")
	E.set_active(TRUE)
	test_time(1)
	TEST_ASSERT(every_running(E), "it runs once its var is set")
	E.set_active(FALSE)
	test_time(2 SECONDS)
	TEST_ASSERT(!every_running(E), "and parks again")

/datum/unit_test/dq_timed_forms/an_ai_op_with_a_range_reach_keeps_its_worker_in_range
/datum/unit_test/dq_timed_forms/an_ai_op_with_a_range_reach_keeps_its_worker_in_range/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	perform_op(H, S, "range", null, ORIGIN_AI, AUTH_AI)
	H.forceMove(get_step(run_loc_floor_bottom_left, NORTH))
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "a worker that steps one tile away still finishes")
	perform_op(H, S, "range", null, ORIGIN_AI, AUTH_AI)
	H.forceMove(locate(run_loc_floor_bottom_left.x, run_loc_floor_bottom_left.y + 3, run_loc_floor_bottom_left.z))
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "a worker three tiles away is stopped")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "and nothing is pending")

/datum/unit_test/dq_timed_forms/a_prompt_an_op_asked_reads_its_holder_through_owner_holder
/datum/unit_test/dq_timed_forms/a_prompt_an_op_asked_reads_its_holder_through_owner_holder/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "ask_check")
	test_answer(H, TRUE)
	TEST_ASSERT_EQUAL(S.done, 1, "the question stayed open and its answer went through")

/datum/unit_test/dq_timed_forms/a_requirement_on_what_the_actor_wears_is_asked_again
/datum/unit_test/dq_timed_forms/a_requirement_on_what_the_actor_wears_is_asked_again/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "worn")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "the wait is pending")
	var/obj/item/clothing/mask/surgical/mask = allocate(/obj/item/clothing/mask/surgical, run_loc_floor_bottom_left)
	H.equip_to_slot_or_del(mask, SLOT_ID_MASK)
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 0, "putting a mask on during the wait ended it")

/datum/unit_test/dq_timed_forms/periodic_work_ticks_under_test_time
/datum/unit_test/dq_timed_forms/periodic_work_ticks_under_test_time/run_forms()
	var/obj/tf_periodic/P = allocate(/obj/tf_periodic, run_loc_floor_bottom_left)
	cadence_start(P, PERIODIC_SLOW)
	test_time(30 SECONDS)
	TEST_ASSERT(P.steps >= 1, "a member of PERIODIC_SLOW stepped (stepped [P.steps] times)")
	cadence_stop(P)

/datum/unit_test/dq_timed_forms/a_refused_input_stops_nothing
/datum/unit_test/dq_timed_forms/a_refused_input_stops_nothing/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "claimer")
	test_menu(H, S, "blocked_body")
	TEST_ASSERT_NOTNULL(op_pending_for(H, "claimer"), "the older wait is still pending: the refused input did not stop it")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "and it finished")

/datum/unit_test/dq_timed_forms/a_start_handler_that_writes_tracked_state_leaves_the_keeps_alone
/datum/unit_test/dq_timed_forms/a_start_handler_that_writes_tracked_state_leaves_the_keeps_alone/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/tf_site/S = site()
	test_menu(H, S, "startw")
	TEST_ASSERT_EQUAL(S.amount, 2, "the start handler wrote the tracked var")
	H.forceMove(get_step(H, EAST))
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 0, "moving still ended the wait (the keeps were set before the start handler ran)")
