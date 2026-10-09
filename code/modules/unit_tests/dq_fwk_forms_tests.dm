// The framework forms of the K19-K25 gaps (doc/rewrite/framework_gaps.md): wait(repeats =, after_step =), wait_until() and release_op(), perform_op(with =) with
// takes(), asks(keeps_answer =), MSG_BALLOON and costs(locked =). Fixtures: code/tests/engine/fwk_forms_fixtures.dm.

/datum/unit_test/dq_fwk_forms
	abstract_type = /datum/unit_test/dq_fwk_forms

/datum/unit_test/dq_fwk_forms/Run()
	test_driver_begin()
	run_forms()
	test_driver_end()

/datum/unit_test/dq_fwk_forms/proc/run_forms()
	return

/datum/unit_test/dq_fwk_forms/proc/person(person_type = /mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(person_type, run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/datum/unit_test/dq_fwk_forms/proc/site()
	return allocate(/obj/fwk_site, run_loc_floor_bottom_left)

// ---- K19: a repeating wait ----

/datum/unit_test/dq_fwk_forms/repeating_wait_runs_laps_until_the_handler_stops
/datum/unit_test/dq_fwk_forms/repeating_wait_runs_laps_until_the_handler_stops/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	test_menu(H, S, "fill")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "one pending op for the whole series")
	test_time(2.5 SECONDS)
	TEST_ASSERT_EQUAL(S.bags, 1, "the first lap effect ran")
	TEST_ASSERT_EQUAL(S.done, 0, "then() waits for the end of the series")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "and it is the same pending op")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.bags, 2, "the second lap")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.bags, 3, "the third lap")
	TEST_ASSERT_EQUAL(S.done, 1, "the handler said stop, so then() ran once")
	TEST_ASSERT_EQUAL(S.laps_seen, 3, "and read every lap")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "nothing is pending")

/datum/unit_test/dq_fwk_forms/repeating_wait_interrupt_keeps_the_laps_done
/datum/unit_test/dq_fwk_forms/repeating_wait_interrupt_keeps_the_laps_done/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	test_menu(H, S, "fill")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(S.bags, 1, "one lap finished")
	H.forceMove(get_step(H, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(S.bags, 1, "walking away ended the series: no second lap")
	TEST_ASSERT_EQUAL(S.done, 0, "then() never ran")
	TEST_ASSERT_EQUAL(S.broke, 1, "on_interrupt ran once")
	TEST_ASSERT_EQUAL(S.broke_laps, 1, "and it could read the laps done")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "nothing is pending")

/datum/unit_test/dq_fwk_forms/repeating_wait_with_nothing_to_do_ends_after_one_lap
/datum/unit_test/dq_fwk_forms/repeating_wait_with_nothing_to_do_ends_after_one_lap/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	S.set_bags(5)
	test_menu(H, S, "fill")
	test_time(2.5 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "the first lap is always taken, and the handler stopped the series")
	TEST_ASSERT_EQUAL(S.laps_seen, 1, "after one lap")

// ---- K20: an unbounded hold ----

/datum/unit_test/dq_fwk_forms/a_hold_lasts_until_released
/datum/unit_test/dq_fwk_forms/a_hold_lasts_until_released/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	test_menu(H, S, "hold")
	test_time(60 SECONDS)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "a minute later it is still held")
	TEST_ASSERT_EQUAL(S.done, 0, "and has not finished")
	TEST_ASSERT(release_op(H, "hold"), "release_op finds the hold")
	TEST_ASSERT_EQUAL(S.done, 1, "releasing runs the rest of the op")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "and nothing is pending")
	TEST_ASSERT(!release_op(H, "hold"), "a second release finds nothing")

/datum/unit_test/dq_fwk_forms/a_hold_breaks_when_the_actor_moves
/datum/unit_test/dq_fwk_forms/a_hold_breaks_when_the_actor_moves/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	test_menu(H, S, "hold")
	test_time(10 SECONDS)
	H.forceMove(get_step(H, EAST))
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(S.done, 0, "a broken keep does not complete the op")
	TEST_ASSERT_EQUAL(S.broke, 1, "on_interrupt is the release")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "nothing is pending")

/datum/unit_test/dq_fwk_forms/a_hold_ends_when_its_condition_holds
/datum/unit_test/dq_fwk_forms/a_hold_ends_when_its_condition_holds/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	test_menu(H, S, "hold_gate")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 0, "held while the gate is shut")
	S.set_gate(TRUE)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(S.done, 1, "it ended the moment the gate opened")
	test_menu(H, S, "hold_gate")
	TEST_ASSERT_EQUAL(S.done, 2, "with the gate already open the hold is skipped")

// ---- K21: perform_op with arguments ----

/datum/unit_test/dq_fwk_forms/perform_op_passes_the_values_an_op_takes
/datum/unit_test/dq_fwk_forms/perform_op_passes_the_values_an_op_takes/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	perform_op(H, S, "hook", null, ORIGIN_AI, AUTH_AI, with = list("dest" = "the vent", "time" = 4 SECONDS, "bogus" = 99))
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 0, "the wait took the length the hook passed")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "and then ran")
	TEST_ASSERT_EQUAL(S.hook_dest, "the vent", "then() read a passed value")
	TEST_ASSERT_NULL(S.hook_bogus, "a value the op does not take was dropped")

/datum/unit_test/dq_fwk_forms/perform_op_without_values_uses_the_defaults
/datum/unit_test/dq_fwk_forms/perform_op_without_values_uses_the_defaults/run_forms()
	var/mob/living/carbon/human/H = person()
	var/obj/fwk_site/S = site()
	perform_op(H, S, "hook", null, ORIGIN_AI, AUTH_AI)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "the default length applied")
	TEST_ASSERT_NULL(S.hook_dest, "and no value was passed")

// ---- K22: a prompt answer as a keep ----

/datum/unit_test/dq_fwk_forms/the_answered_target_is_kept_across_the_wait
/datum/unit_test/dq_fwk_forms/the_answered_target_is_kept_across_the_wait/run_forms()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/T = allocate(/mob/living/carbon/human, get_step(run_loc_floor_bottom_left, NORTH))
	var/obj/fwk_site/S = site()
	S.candidates = list(T)
	test_prompts_reset()
	test_menu(H, S, "pick")
	test_answer(H, T)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "waiting on the answered person")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "they stayed, so the op ran")
	TEST_ASSERT(S.picked == T, "and then() read the answered target")
	GLOB.test_prompts = null

/datum/unit_test/dq_fwk_forms/the_answered_target_leaving_reach_ends_the_wait
/datum/unit_test/dq_fwk_forms/the_answered_target_leaving_reach_ends_the_wait/run_forms()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/T = allocate(/mob/living/carbon/human, get_step(run_loc_floor_bottom_left, NORTH))
	var/obj/fwk_site/S = site()
	S.candidates = list(T)
	test_prompts_reset()
	test_menu(H, S, "pick")
	test_answer(H, T)
	test_time(1 SECOND)
	T.forceMove(locate(run_loc_floor_bottom_left.x, run_loc_floor_bottom_left.y + 4, run_loc_floor_bottom_left.z))
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 0, "the answered person walked away, so nothing happened")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "and nothing is pending")
	GLOB.test_prompts = null

// ---- K24: a balloon refusal ----

/datum/unit_test/dq_fwk_forms/a_balloon_refusal_goes_to_the_balloon_not_chat
/datum/unit_test/dq_fwk_forms/a_balloon_refusal_goes_to_the_balloon_not_chat/run_forms()
	var/mob/living/carbon/human/fwk_tester/H = person(/mob/living/carbon/human/fwk_tester)
	var/obj/fwk_site/S = site()
	var/datum/op_result/result = test_menu(H, S, "quick")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the requirement refused")
	TEST_ASSERT_EQUAL(H.balloon_text, "Too quick.", "the refusal showed as a balloon")
	TEST_ASSERT_EQUAL(H.chat_refusals, 0, "and wrote nothing to chat")

// ---- K25: a cost read when the wait starts ----

/datum/unit_test/dq_fwk_forms/a_locked_cost_is_read_when_the_wait_starts
/datum/unit_test/dq_fwk_forms/a_locked_cost_is_read_when_the_wait_starts/run_forms()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/fwk_site/S = site()
	M.dark_energy = 100
	S.charge = 10
	test_ui(M, S, "drain", list())
	S.charge = 40
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(S.done, 1, "the op ran")
	TEST_ASSERT_EQUAL(M.dark_energy, 90, "the amount the wait started with was spent")
	S.charge = 10
	test_ui(M, S, "drain_live", list())
	S.charge = 40
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(M.dark_energy, 50, "an unlocked cost is read again at the end of the wait")

// ---- the converted sites that prove K24 and K22/K21: the tourniquet cinch ----

/datum/unit_test/dq_fwk_forms/tourniquet_refusal_is_a_balloon_and_the_cinch_completes
/datum/unit_test/dq_fwk_forms/tourniquet_refusal_is_a_balloon_and_the_cinch_completes/run_forms()
	var/mob/living/carbon/human/fwk_tester/H = person(/mob/living/carbon/human/fwk_tester)
	var/mob/living/carbon/human/P = allocate(/mob/living/carbon/human, get_step(run_loc_floor_bottom_left, NORTH))
	dq_give_zone_sel(H)
	var/obj/item/tourniquet/Q = allocate(/obj/item/tourniquet, run_loc_floor_bottom_left)
	H.put_in_active_hand(Q)
	H.zone_sel.selecting = BP_TORSO
	test_click(H, P, Q)
	TEST_ASSERT_EQUAL(H.balloon_text, "a tourniquet goes on an arm or a leg!", "the torso refusal is a balloon")
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 0, "and nothing waits")
	H.zone_sel.selecting = BP_L_ARM
	var/obj/item/organ/external/arm = P.get_organ(BP_L_ARM)
	test_click(H, P, Q)
	TEST_ASSERT_EQUAL(length(op_pendings_of(H)), 1, "an arm starts the cinch")
	H.zone_sel.selecting = BP_TORSO // aiming elsewhere meanwhile changes nothing: the limb was fixed when it began
	test_time(4 SECONDS)
	TEST_ASSERT(arm.tourniquet == Q, "the tourniquet went on the arm that was aimed at")
