/// Walking preserves the trap; running causes real pain and consumes it.
/datum/unit_test/interim_lego_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/lego/trap = allocate(/obj/item/lego, T)
	TEST_ASSERT(!user.has_affliction(/datum/affliction/acute_pain), "the actor starts without acute pain")
	user.m_intent = I_WALK
	trap.Crossed(user)
	TEST_ASSERT(!QDELETED(trap), "walking over the trap preserves it")
	TEST_ASSERT(!user.has_affliction(/datum/affliction/acute_pain), "walking over the trap inflicts no pain")
	user.m_intent = I_RUN
	trap.Crossed(user)
	TEST_ASSERT(QDELETED(trap), "running over the trap consumes it")
	TEST_ASSERT(user.has_affliction(/datum/affliction/acute_pain), "running over the trap inflicts real acute pain")
	TEST_ASSERT(user.body.get_pain() > 0, "the actual injury increases the body's pain")
