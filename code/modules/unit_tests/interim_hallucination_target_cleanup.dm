/datum/unit_test/interim_hallucination_target_cleanup
	var/invalid_mode = 1

/datum/unit_test/interim_hallucination_target_cleanup/deleted
	invalid_mode = 2

/datum/unit_test/interim_hallucination_target_cleanup/nonhuman
	invalid_mode = 3

/datum/unit_test/interim_hallucination_target_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	target.status_at_least(STAT_HALLUCINATING, (30 SECONDS) / (1 SECOND))
	TEST_ASSERT(target.has_status(STAT_HALLUCINATING), "The actual target genuinely has its real hallucination status")
	var/obj/effect/fake_attacker/human/effect = allocate(/obj/effect/fake_attacker/human, T, target, target)
	TEST_ASSERT(effect && !QDELETED(effect) && effect.loc == T, "The real hallucination completes its actual target-and-appearance constructor")
	TEST_ASSERT_EQUAL(effect.name, target.name, "The actual constructor copies its real original appearance source name")
	TEST_ASSERT(effect.requires_hallucinating, "The actual effect retains its original hallucination requirement")
	TEST_ASSERT_EQUAL(effect.fake_attacker_human_step(null), target, "The actual valid-target periodic path returns the exact original hallucinating human")
	TEST_ASSERT(!QDELETED(effect), "The actual valid-target control preserves its original effect")
	var/mob/living/replacement
	if(invalid_mode == 1)
		target.status_set(STAT_HALLUCINATING, 0)
		TEST_ASSERT(!target.has_status(STAT_HALLUCINATING), "The actual target genuinely loses its real hallucination status")
	else if(invalid_mode == 2)
		TEST_ASSERT(consume(target), "The actual original target is genuinely removed through its public lifecycle")
		TEST_ASSERT(QDELETED(target), "The actual original target is deleted before orphan cleanup")
	else
		replacement = allocate(/mob/living/simple_mob/animal/passive/cat, T)
		TEST_ASSERT(!ishuman(replacement) && !QDELETED(replacement), "The actual replacement target is a real living non-human")
		effect.set_target(replacement)
	TEST_ASSERT_NULL(effect.fake_attacker_human_step(null), "The actual invalid-target periodic path preserves its original null result")
	TEST_ASSERT(QDELETED(effect), "The actual invalid-target endpoint consumes the exact original hallucination effect")
	if(invalid_mode != 2)
		TEST_ASSERT(!QDELETED(target) && target.loc == T, "Actual invalid-target cleanup preserves the original human target")
	if(replacement)
		TEST_ASSERT(!QDELETED(replacement) && replacement.loc == T, "Actual target-type cleanup preserves the exact real non-human target")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual hallucination cleanup preserves the unrelated original floor item")
