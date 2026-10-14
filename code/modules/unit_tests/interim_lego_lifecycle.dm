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

/// Observe the real report formatter while retaining the production admin broadcast.
/obj/structure/gootrap/interim_actor_probe
	var/reported_actor_ref
	var/reported_message
	var/report_count = 0

/obj/structure/gootrap/interim_actor_probe/crossing_admin_message(mob/living/victim)
	reported_actor_ref = victim ? REF(victim) : null
	report_count++
	. = ..(victim)
	reported_message = .

/datum/unit_test/interim_gootrap_crossing_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	var/obj/structure/gootrap/interim_actor_probe/trap = allocate(/obj/structure/gootrap/interim_actor_probe, T)
	victim.m_intent = I_WALK
	trap.Crossed(victim)
	TEST_ASSERT(trap.deployed, "walking leaves the goo trap deployed")
	TEST_ASSERT_NULL(victim.buckled_to(), "walking does not restrain the actor")
	TEST_ASSERT_EQUAL(trap.report_count, 0, "walking produces no crossing report")
	victim.m_intent = I_RUN
	trap.Crossed(victim)
	TEST_ASSERT(!trap.deployed, "running triggers the trap")
	TEST_ASSERT_EQUAL(victim.buckled_to(), trap, "the actual crossing victim is restrained by the real trap")
	TEST_ASSERT_EQUAL(trap.report_count, 1, "the triggered crossing produces exactly one report")
	TEST_ASSERT_EQUAL(trap.reported_actor_ref, REF(victim), "the crossing report receives the actual victim")
	TEST_ASSERT_EQUAL(trap.reported_message, "[key_name(victim)] has stepped in the goo trap.", "the real admin report names the actual crossing victim")
