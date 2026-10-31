// Behaviour pins for rewrite/missing-forms: a malfunctioning AI's priced abilities. An ability asks first (a confirmation or a choice) and its CPU
// is spent only when the AI says yes; an AI that cannot pay is not asked, and one that can no longer pay when it answers gets nothing and pays
// nothing. Driven as the AI uses them: the ability verb, then the answer. Written against the custom malf prompt kinds and pinned green on them
// before the cost became a resource the request reserves.

/datum/unit_test/dq_mfo_malf
	abstract_type = /datum/unit_test/dq_mfo_malf
	var/mob/living/silicon/ai/ai

/datum/unit_test/dq_mfo_malf/Run()
	test_driver_begin()
	p2cl_capture_prompts()
	ai = allocate(/mob/living/silicon/ai, run_loc_floor_bottom_left, null, null, null, TRUE)
	ai.setup_for_malf()
	ai.research.max_cpu = 1000
	ai.research.stored_cpu = 100
	ai.research.cpu_increase_per_tick = 0
	run_malf()
	test_driver_end()

/datum/unit_test/dq_mfo_malf/proc/run_malf()
	return

/// The AI uses ability `verb_path` (with `target` when the ability takes one).
/datum/unit_test/dq_mfo_malf/proc/use(verb_path, target)
	usr = ai
	if(target)
		call(ai, verb_path)(target)
	else
		call(ai, verb_path)()
	test_time(1)

/datum/unit_test/dq_mfo_malf/proc/answer(value)
	p2cl_answer(ai, value)
	test_time(1)

/datum/unit_test/dq_mfo_malf/proc/cpu()
	return ai.research.stored_cpu

/// Yes spends the price; no spends nothing.
/datum/unit_test/dq_mfo_malf/confirm_spends_only_on_yes

/datum/unit_test/dq_mfo_malf/confirm_spends_only_on_yes/run_malf()
	use(/datum/game_mode/malfunction/verb/recall_shuttle)
	answer(FALSE)
	TEST_ASSERT_EQUAL(cpu(), 100, "no: nothing spent")
	use(/datum/game_mode/malfunction/verb/recall_shuttle)
	answer(TRUE)
	TEST_ASSERT_EQUAL(cpu(), 75, "yes: the 25 CPU price is spent")

/// An AI that cannot pay is not asked; one that cannot pay any more when it answers pays nothing.
/datum/unit_test/dq_mfo_malf/unaffordable

/datum/unit_test/dq_mfo_malf/unaffordable/run_malf()
	ai.research.stored_cpu = 10
	use(/datum/game_mode/malfunction/verb/recall_shuttle)
	answer(TRUE)
	TEST_ASSERT_EQUAL(cpu(), 10, "too poor to be asked: nothing spent")
	ai.research.stored_cpu = 100
	use(/datum/game_mode/malfunction/verb/recall_shuttle)
	ai.research.stored_cpu = 10
	answer(TRUE)
	TEST_ASSERT_EQUAL(cpu(), 10, "too poor by the answer: nothing spent")

/// A priced choice: the price is paid on the pick, not on a closed question.
/datum/unit_test/dq_mfo_malf/camera_upgrade

/datum/unit_test/dq_mfo_malf/camera_upgrade/run_malf()
	var/obj/machinery/camera/C = allocate(/obj/machinery/camera, get_step(run_loc_floor_bottom_left, EAST))
	ai.research.stored_cpu = 250
	use(/datum/game_mode/malfunction/verb/hack_camera, C)
	answer("Add X-Ray")
	TEST_ASSERT_EQUAL(cpu(), 150, "the pick costs 100 CPU")
	use(/datum/game_mode/malfunction/verb/hack_camera, C)
	p2cl_answer(ai, null, TRUE)
	test_time(1)
	TEST_ASSERT_EQUAL(cpu(), 150, "closing the question costs nothing")
