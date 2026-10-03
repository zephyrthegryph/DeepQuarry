/// Real floor runes hide and reveal through BYOND visibility compatibility behavior.
/datum/unit_test/interim_rune_visibility_endings
	var/reveal = FALSE
	var/empty = FALSE

/datum/unit_test/interim_rune_visibility_endings/reveal
	reveal = TRUE

/datum/unit_test/interim_rune_visibility_endings/empty
	empty = TRUE

/datum/unit_test/interim_rune_visibility_endings/reveal_empty
	reveal = TRUE
	empty = TRUE

/datum/unit_test/interim_rune_visibility_endings/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/adjacent = get_step(T, EAST)
	TEST_ASSERT(adjacent, "the actual rune fixture has an adjacent target floor")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/effect/rune/source = allocate(/obj/effect/rune, T)
	TEST_ASSERT(source in REGISTRY_MEMBERS(REGISTRY_RUNES), "the real source rune registers on initialization")
	TEST_ASSERT_EQUAL(length(range(6, source) & REGISTRY_MEMBERS(REGISTRY_RUNES)), 1, "the fixture initially contains only its source rune")
	var/obj/effect/rune/target
	if(!empty)
		target = allocate(/obj/effect/rune, adjacent)
		TEST_ASSERT_EQUAL(target.invisibility, 0, "the actual adjacent rune starts visibly rendered")
		if(reveal)
			target.set_invisibility(INVISIBILITY_OBSERVER)
			TEST_ASSERT_EQUAL(target.visibility, FALSE, "the actual reveal target starts hidden")
	if(reveal)
		source.revealrunes(source, user)
	else
		source.obscure(4, user)
	if(empty)
		TEST_ASSERT(!QDELETED(source), "an actual visibility ritual with no neighboring rune preserves its source")
		TEST_ASSERT(source in REGISTRY_MEMBERS(REGISTRY_RUNES), "the failed ritual preserves actual registry membership")
		TEST_ASSERT_EQUAL(source.loc, T, "the failed ritual leaves the original source on its original floor")
	else
		TEST_ASSERT(QDELETED(source), "a successful actual visibility ritual consumes its source rune")
		TEST_ASSERT(!(source in REGISTRY_MEMBERS(REGISTRY_RUNES)), "consumption unregisters the actual source rune")
		TEST_ASSERT(!QDELETED(target), "the actual visibility ritual preserves its exact neighboring rune")
		TEST_ASSERT(target in REGISTRY_MEMBERS(REGISTRY_RUNES), "the neighboring rune stays registered")
		TEST_ASSERT_EQUAL(target.loc, adjacent, "the neighboring rune stays on its original floor")
		if(reveal)
			TEST_ASSERT_EQUAL(target.visibility, TRUE, "actual reveal enables BYOND historical boolean visibility")
			TEST_ASSERT_EQUAL(target.invisibility, INVISIBILITY_NONE, "actual reveal makes the hidden neighboring rune visible again")
		else
			TEST_ASSERT_EQUAL(target.invisibility, INVISIBILITY_OBSERVER, "actual obscure hides the neighboring rune from living observers")
			TEST_ASSERT_EQUAL(target.visibility, FALSE, "actual obscure disables BYOND historical boolean visibility")
	TEST_ASSERT(!QDELETED(user), "either actual visibility ritual preserves its living invoker")
