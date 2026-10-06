// The mob repeats that moved from DECLARE_REPEAT to a type-level every() gated on a tracked var (doc/rewrite/om_retirement.md):
// each runs while its var holds, parks when the handler clears it, and the old REPEAT_STOP paths still end the work.

/// The jittery shake runs while the status does; a death ends the status at the next shake.
/datum/unit_test/life_om/shake_ends_on_death

/datum/unit_test/life_om/shake_ends_on_death/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.status_adjust(STAT_JITTERY, 500)
	TEST_ASSERT(H.jittery_shaking, "the status start sets the shake's gate")
	H.death()
	life_test_advance(0.5)
	TEST_ASSERT(!H.has_status(STAT_JITTERY), "the dead stop jittering")
	TEST_ASSERT(!H.jittery_shaking, "and the shake parks")
	TEST_ASSERT_EQUAL(H.pixel_x, H.old_x, "with the offset reset")

/// The transform animation plays its drill sounds 0.8 s apart, then ends the lockdown it started.
/datum/unit_test/life_om/robot_transform_sounds_end_the_lockdown

/datum/unit_test/life_om/robot_transform_sounds_end_the_lockdown/run_life()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	TEST_ASSERT(life_test_place(R), "no floor to place the test robot on")
	R.do_transform_animation()
	TEST_ASSERT_EQUAL(R.transform_sounds_left, 7, "seven steps to go")
	TEST_ASSERT(R.notransform, "the robot is held while it transforms")
	life_test_advance(3 * 0.8 + 0.1)
	TEST_ASSERT_EQUAL(R.transform_sounds_left, 4, "one step every 0.8 seconds")
	life_test_advance(4 * 0.8)
	TEST_ASSERT_EQUAL(R.transform_sounds_left, 0, "the countdown ends")
	TEST_ASSERT(!R.notransform, "and the lockdown with it")
	TEST_ASSERT(!R.anchored, "the robot is free to move")

/// A burst macrophage holding no human dies at its 3 minute check, and the check parks.
/datum/unit_test/life_om/macrophage_deathwatch

/datum/unit_test/life_om/macrophage_deathwatch/run_life()
	var/mob/living/simple_mob/vore/aggressive/macrophage/M = allocate(/mob/living/simple_mob/vore/aggressive/macrophage)
	TEST_ASSERT(life_test_place(M), "no floor to place the test macrophage on")
	var/turf/T = get_turf(M)
	M.set_deathwatch(TRUE)
	life_test_advance(2 * 60)
	TEST_ASSERT(M.stat != DEAD, "alive before the check")
	life_test_advance(60 + 1)
	TEST_ASSERT_EQUAL(M.stat, DEAD, "the check kills it")
	TEST_ASSERT(!M.deathwatch, "and clears its gate")
	qdel(M)
	life_test_advance(5)
	// The corpse bleeds where it lay (wherever that ended up): sweep what it left.
	for(var/obj/effect/decal/cleanable/blood/B in world)
		if(B.z == T.z && get_dist(B, T) <= 7)
			qdel(B)

/// A chain with no target to attack ends at the next attack and parks.
/datum/unit_test/life_om/jellyfish_chain_needs_a_target

/datum/unit_test/life_om/jellyfish_chain_needs_a_target/run_life()
	var/mob/living/simple_mob/vore/boss_jellyfish/J = allocate(/mob/living/simple_mob/vore/boss_jellyfish)
	TEST_ASSERT(life_test_place(J), "no floor to place the test jellyfish on")
	J.set_chain_number(3)
	life_test_advance(4 + 0.1)
	TEST_ASSERT_EQUAL(J.chain_number, 0, "no target: the chain ends")
	TEST_ASSERT_EQUAL(J.icon_state, "jellyfish", "back to its idle look")

/// A dream shows its fragments one every dream_wait while the dreamer sleeps, and waking ends it.
/datum/unit_test/life_om/dream_ends_on_waking

/datum/unit_test/life_om/dream_ends_on_waking/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.set_stat(UNCONSCIOUS)
	H.set_dream_fragments(list("one", "two", "three"))
	life_test_advance(0.2)
	TEST_ASSERT_EQUAL(length(H.dream_fragments), 2, "the first fragment shows at once")
	H.set_stat(CONSCIOUS)
	life_test_advance(3.1)
	TEST_ASSERT(isnull(H.dream_fragments), "waking ends the dream")
