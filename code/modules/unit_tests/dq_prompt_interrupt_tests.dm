// An op paused at a prompt holds what it holds while it waits: losing any of it (the actor, the target, the held item, reach, the power the op
// needs) cancels the op and closes the prompt with the wait's feedback; an answer re-runs the requirements; keeps = 0 opts out of the actor-side keeps.

/datum/unit_test/dq_prompt_interrupt
	abstract_type = /datum/unit_test/dq_prompt_interrupt

/datum/unit_test/dq_prompt_interrupt/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_prompt_interrupt/proc/run_gate()
	return

/// Picks the op and checks its prompt is open.
/datum/unit_test/dq_prompt_interrupt/proc/open(mob/living/carbon/human/H, obj/e0_fixture/prompt_base/B, obj/item/held = null)
	test_click(H, B, held)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the prompt is open")
	TEST_ASSERT_NOTNULL(op_pending_of(H)?.request, "the op waits on its request")

/datum/unit_test/dq_prompt_interrupt/proc/make_person()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/datum/unit_test/dq_prompt_interrupt/proc/make_box(type = /obj/e0_fixture/prompt_base/box)
	return allocate(type, run_loc_floor_bottom_left)

/datum/unit_test/dq_prompt_interrupt/proc/far_away()
	return locate(run_loc_floor_bottom_left.x + 3, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)

/datum/unit_test/dq_prompt_interrupt/answers_when_nothing_changed
/datum/unit_test/dq_prompt_interrupt/answers_when_nothing_changed/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	open(H, B)
	test_answer(H, 7)
	TEST_ASSERT_EQUAL(B.value, 7, "the answer was applied")
	TEST_ASSERT_NULL(op_pending_of(H), "and nothing is pending")

/datum/unit_test/dq_prompt_interrupt/walking_away_closes_the_prompt
/datum/unit_test/dq_prompt_interrupt/walking_away_closes_the_prompt/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	open(H, B)
	var/datum/request/R = op_pending_of(H).request
	H.forceMove(far_away())
	test_time(1)
	TEST_ASSERT_NULL(op_pending_of(H), "the op was cancelled")
	TEST_ASSERT(!R.is_open(), "and its prompt closed")
	test_answer(H, 7)
	TEST_ASSERT_EQUAL(B.runs, 0, "a late answer runs nothing")

/datum/unit_test/dq_prompt_interrupt/dropping_the_held_item_closes_the_prompt
/datum/unit_test/dq_prompt_interrupt/dropping_the_held_item_closes_the_prompt/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	var/obj/item/pen/P = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(P)
	open(H, B, P)
	H.drop_item()
	test_time(1)
	TEST_ASSERT_NULL(op_pending_of(H), "dropping what the actor held cancelled the op")
	test_answer(H, 7)
	TEST_ASSERT_EQUAL(B.runs, 0, "a late answer runs nothing")

/datum/unit_test/dq_prompt_interrupt/the_target_deleted_closes_the_prompt
/datum/unit_test/dq_prompt_interrupt/the_target_deleted_closes_the_prompt/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	open(H, B)
	var/datum/request/R = op_pending_of(H).request
	qdel(B)
	test_time(1)
	TEST_ASSERT_NULL(op_pending_of(H), "the op was cancelled")
	TEST_ASSERT(!R.is_open(), "and its prompt closed")

/datum/unit_test/dq_prompt_interrupt/losing_power_closes_the_prompt
/datum/unit_test/dq_prompt_interrupt/losing_power_closes_the_prompt/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	open(H, B)
	var/datum/request/R = op_pending_of(H).request
	B.set_powered(FALSE)
	test_time(1)
	TEST_ASSERT_NULL(op_pending_of(H), "the machine lost power: the op was cancelled")
	TEST_ASSERT(!R.is_open(), "and its prompt closed")
	TEST_ASSERT_EQUAL(B.runs, 0, "nothing ran")

/datum/unit_test/dq_prompt_interrupt/an_answer_re_runs_the_requirements
/datum/unit_test/dq_prompt_interrupt/an_answer_re_runs_the_requirements/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box()
	open(H, B)
	// the world changed without publishing a read the op watches: the answer still meets the requirement
	B.powered = FALSE
	var/datum/op_result/result = test_answer(H, 7)
	TEST_ASSERT_EQUAL(B.runs, 0, "the op did not run")
	TEST_ASSERT_EQUAL(result?.reason, MSG(prompt/unpowered), "it refused with the requirement's reason")

/datum/unit_test/dq_prompt_interrupt/keeps_zero_survives_walking_away
/datum/unit_test/dq_prompt_interrupt/keeps_zero_survives_walking_away/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box(/obj/e0_fixture/prompt_base/keeps)
	open(H, B)
	H.forceMove(far_away())
	test_time(1)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "keeps = 0 outlives the actor walking away")
	test_answer(H, 7)
	TEST_ASSERT_EQUAL(B.value, 7, "and the answer is applied")

/datum/unit_test/dq_prompt_interrupt/a_chain_carries_its_answers
/datum/unit_test/dq_prompt_interrupt/a_chain_carries_its_answers/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box(/obj/e0_fixture/prompt_base/chain)
	open(H, B)
	test_answer(H, 3)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the second step asks")
	test_answer(H, 9)
	TEST_ASSERT_EQUAL(B.value, 3, "the first answer is in the op")
	TEST_ASSERT_EQUAL(B.second, 9, "and the second")

/datum/unit_test/dq_prompt_interrupt/a_chain_cancelled_between_steps
/datum/unit_test/dq_prompt_interrupt/a_chain_cancelled_between_steps/run_gate()
	var/mob/living/carbon/human/H = make_person()
	var/obj/e0_fixture/prompt_base/B = make_box(/obj/e0_fixture/prompt_base/chain)
	open(H, B)
	test_answer(H, 3)
	B.set_powered(FALSE)
	test_time(1)
	TEST_ASSERT_NULL(op_pending_of(H), "power lost at the second prompt cancels the chain")
	TEST_ASSERT_EQUAL(B.runs, 0, "and nothing ran")
