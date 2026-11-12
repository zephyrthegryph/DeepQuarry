/// A slime's feeding check is silent and answers why: the AI asks it every attack and consume() every bite, so it returns a reason
/// (null when the slime can feed) instead of printing one.
/datum/unit_test/dq_slime_consume_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/simple_mob/slime/xenobio/slime = allocate(/mob/living/simple_mob/slime/xenobio, T)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(istext(slime.consume_refusal(null)), "feeding on nothing is refused with a reason")
	var/mob/living/simple_mob/slime/xenobio/other = allocate(/mob/living/simple_mob/slime/xenobio, T)
	TEST_ASSERT(istext(slime.consume_refusal(other)), "a slime cannot feed on another slime")
	TEST_ASSERT_NULL(slime.consume_refusal(victim), "an adjacent unarmoured human can be fed on")
	slime.harmless = TRUE
	TEST_ASSERT(istext(slime.consume_refusal(victim)), "a pacified slime refuses to feed")
