// What wakes a human's sleeping life_status step: a var it reads (resting, embedded_flag) written through its setter. The step declares both in its
// reads (life_steps.dm); a tracked write publishes the var to the sequence, so the step needs no hand-written wake.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/life_om/status_wake
	abstract_type = /datum/unit_test/life_om/status_wake
	var/mob/living/carbon/human/H

/// A human on a floor whose life_status step has fallen asleep. FALSE (and a failure saying why) when it never does.
/datum/unit_test/life_om/status_wake/proc/sleeper()
	H = allocate(/mob/living/carbon/human)
	// A clientless human counts as SSD, which keeps the status step awake; a teleoperated one is awake as a player's is.
	H.teleop = H
	if(!life_test_place(H))
		TEST_FAIL("no floor to place the test human on")
		return FALSE
	for(var/i in 1 to 10)
		life_test_advance(LIFE_CYCLE_SECONDS)
		if(life_test_asleep(H, "life_status"))
			return TRUE
	var/obj/item/organ/vision = H.species.vision_organ ? H.organ_in(H.species.vision_organ) : null
	TEST_FAIL("life_status never slept in a healthy human (awake: [jointext(life_test_awake(H), ", ")]; stat [H.stat], afflictions [LAZYLEN(H.body?.afflictions)], dirty [H.body?.dirty], pain [H.current_pain()], oxygen debt [H.oxygen_debt()], critical [H.is_critical()], vision [H.species.vision_organ ? (vision ? (vision.is_bruised() ? "bruised" : "ok") : "missing") : "n/a"], statuses [H.status_units(STAT_TIREDNESS)]/[H.status_units(STAT_FEAR)], ear [H.ear_damage], sdisabilities [H.sdisabilities], ssd [H.species.get_ssd(H)]); the test can't show it waking")
	return FALSE

/// Lying down wakes the status step (resting is one of its reads).
/datum/unit_test/life_om/status_wake/resting

/datum/unit_test/life_om/status_wake/resting/run_life()
	if(!sleeper())
		return
	H.set_resting(TRUE)
	TEST_ASSERT(!life_test_asleep(H, "life_status"), "lying down woke the status step")

/// An object lodging in the body wakes it (embedded_flag is one of its reads).
/datum/unit_test/life_om/status_wake/embedded_object

/datum/unit_test/life_om/status_wake/embedded_object/run_life()
	if(!sleeper())
		return
	H.set_embedded_flag(1)
	TEST_ASSERT(!life_test_asleep(H, "life_status"), "an embedded object woke the status step")

#endif
