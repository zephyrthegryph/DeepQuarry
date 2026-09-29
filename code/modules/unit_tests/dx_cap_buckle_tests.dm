// buckle() (code/datums/capabilities/library/buckle.dm).

/obj/cap_fixture/seat/capabilities()
	. = ..()
	. += cap_buckle(max = 2, lying = TRUE)

/datum/unit_test/dx_cap_buckle

/datum/unit_test/dx_cap_buckle/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/seat/F = allocate(/obj/cap_fixture/seat, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/sitter = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT(F.can_buckle, "buckle() turns on the buckling system")
	TEST_ASSERT_EQUAL(F.max_buckled_mobs, 2, "max")
	TEST_ASSERT_EQUAL(F.buckle_lying, 1, "lying")

	var/datum/interaction/capability/grab_entry = dx_cap_entry(F, "Buckle")
	var/datum/interaction/capability/release = dx_cap_entry(F, "Unbuckle")
	TEST_ASSERT_NOTNULL(grab_entry, "the Buckle entry")
	TEST_ASSERT_EQUAL(grab_entry.held_type, /obj/item/grab, "Buckle takes a grabbed mob")
	TEST_ASSERT_EQUAL(release.why_not(H, F, null), "nobody is buckled to it", "Unbuckle refuses when empty")
	TEST_ASSERT(!length(F.caps_examine(H)), "no examine line when empty")

	TEST_ASSERT(F.buckle_mob(sitter, forced = TRUE), "the existing system buckles")
	TEST_ASSERT(("[sitter] is buckled to it." in F.caps_examine(H)), "examine names who is buckled")
	TEST_ASSERT_NULL(release.why_not(H, F, null), "Unbuckle is available")
	TEST_ASSERT(release.perform(H, F, null), "Unbuckle performs")
	TEST_ASSERT_NULL(sitter.buckled_to(), "the sitter is free")
	TEST_ASSERT(!F.has_buckled_mobs(), "nobody left")
