// Living abilities (K23): the ops of living_abilities() (code/library/mob/living_abilities.dm) are declared in the one CAPABILITIES(/mob/living) block through
// a library proc, so a species or trait ability on any living mob resolves by key, waits, keeps what it keeps and runs its effect. Each test drives an ability
// the way its verb does (perform_op by key, an answer to its question, the kernel clock) and reads what the mob then has.

/datum/unit_test/dq_living_ability
	abstract_type = /datum/unit_test/dq_living_ability

/datum/unit_test/dq_living_ability/Run()
	test_driver_begin()
	exercise()
	test_driver_end()

/datum/unit_test/dq_living_ability/proc/exercise()
	return

/// The key of an ability the way its verb performs it.
/datum/unit_test/dq_living_ability/proc/use(mob/living/actor, key, list/with = null)
	return perform_op(actor, actor, key, null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = with)

/// A human that cannot be hurt by the test map's air while the clock runs.
/datum/unit_test/dq_living_ability/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// An ability of /mob/living resolves for a living mob and runs after its wait: the revert from a beast form.
/datum/unit_test/dq_living_ability/revert_beast_form_resolves

/datum/unit_test/dq_living_ability/revert_beast_form_resolves/exercise()
	var/mob/living/carbon/human/H = person()
	var/datum/op_result/result = use(H, "revert_beast_form")
	TEST_ASSERT_NOTNULL(result, "the op resolves")
	TEST_ASSERT(result.outcome != ACT_REFUSED, "a living mob is not refused its own ability")
	TEST_ASSERT_NULL(result.outcome, "the op waits")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the actor has a pending op")
	test_time(9 SECONDS)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "ten seconds are not over: [result.outcome] [result.reason] ")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(op_pending_of(H), "the wait ended")
	TEST_ASSERT_EQUAL(result.outcome, ACT_COMMITTED, "and the ability committed")

/// Walking away ends the wait and tells the others the form stopped shifting.
/datum/unit_test/dq_living_ability/revert_beast_form_cancels_on_move

/datum/unit_test/dq_living_ability/revert_beast_form_cancels_on_move/exercise()
	var/mob/living/carbon/human/H = person()
	use(H, "revert_beast_form")
	TEST_ASSERT_NOTNULL(op_pending_of(H), "waiting")
	H.forceMove(get_step(get_turf(H), NORTH))
	test_time(1 SECOND)
	TEST_ASSERT_NULL(op_pending_of(H), "a move ended the wait")
	test_time(11 SECONDS)
	TEST_ASSERT_NULL(op_pending_of(H), "and nothing finished later")

/// The succubus bite carries its victim and its choice into the wait, and lands on the one still there.
/datum/unit_test/dq_living_ability/succubus_bite_injects_after_the_wait

/datum/unit_test/dq_living_ability/succubus_bite_injects_after_the_wait/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(get_step(get_turf(H), NORTH))
	var/datum/op_result/result = use(H, "succubus_bite", list("victim" = V, "choice" = "Numbing", "from" = V.loc))
	TEST_ASSERT_NOTNULL(result, "the op resolves")
	TEST_ASSERT_NULL(result.outcome, "the bite waits")
	test_time(29 SECONDS)
	TEST_ASSERT(!V.bloodstr.has_reagent(REAGENT_ID_NUMBING_FLUID), "nothing is injected before half a minute")
	test_time(2 SECONDS)
	TEST_ASSERT(V.bloodstr.has_reagent(REAGENT_ID_NUMBING_FLUID), "the chosen venom went in: [result.outcome] [result.reason] pend [!!op_pending_of(H)]")

/// A victim who got away before the bite is not bitten.
/datum/unit_test/dq_living_ability/succubus_bite_misses_a_victim_who_left

/datum/unit_test/dq_living_ability/succubus_bite_misses_a_victim_who_left/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(get_step(get_turf(H), NORTH))
	use(H, "succubus_bite", list("victim" = V, "choice" = "Numbing", "from" = V.loc))
	V.forceMove(get_step(get_turf(V), NORTH))
	test_time(31 SECONDS)
	TEST_ASSERT(!V.bloodstr.has_reagent(REAGENT_ID_NUMBING_FLUID), "a victim who is no longer there is not bitten")

/// Egg laying asks first, and the answer reaches the effect.
/datum/unit_test/dq_living_ability/egg_laying_asks_then_waits

/datum/unit_test/dq_living_ability/egg_laying_asks_then_waits/exercise()
	var/mob/living/carbon/human/H = person()
	H.eggs = 0
	var/datum/op_result/result = use(H, "egg_laying")
	TEST_ASSERT_NULL(result?.outcome, "the ability waits on its question")
	TEST_ASSERT_NOTNULL(SSrequests.open_for(H), "it asks what to do")
	var/datum/op_result/waiting = test_answer(H, "Make a Egg")
	TEST_ASSERT_NULL(waiting?.outcome, "an answered question starts the wait")
	test_time(31 SECONDS)
	TEST_ASSERT_EQUAL(H.eggs, 1, "the egg was made: [waiting?.outcome] [waiting?.reason] pend [!!op_pending_of(H)]")

/// The rainbow ability keeps the one it was asked at: when they walk out of sight the charge ends and nothing fires.
/datum/unit_test/dq_living_ability/healing_rainbows_keeps_its_target

/datum/unit_test/dq_living_ability/healing_rainbows_keeps_its_target/exercise()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(get_step(get_turf(H), NORTH))
	var/datum/op_result/result = use(H, "healing_rainbows")
	TEST_ASSERT_NULL(result?.outcome, "the ability waits on its question")
	TEST_ASSERT_NOTNULL(SSrequests.open_for(H), "it asks whom")
	test_answer(H, V)
	TEST_ASSERT_NOTNULL(op_pending_of(H), "the charge runs")
	V.forceMove(get_step(get_turf(V), NORTH))
	test_time(1 SECOND)
	TEST_ASSERT_NULL(op_pending_of(H), "the one asked at moved: the charge ended")
