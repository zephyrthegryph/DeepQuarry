// cap_reach() (code/datums/capabilities/library/reach.dm).

/obj/item/cap_fixture/pole/capabilities()
	. = ..()
	. += cap_reach(tiles = 3)

/datum/unit_test/dx_cap_reach

/datum/unit_test/dx_cap_reach/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/obj/item/cap_fixture/pole/P = allocate(/obj/item/cap_fixture/pole, T)
	TEST_ASSERT_EQUAL(P.reach, 3, "reach written at init")
	TEST_ASSERT("It can strike from 3 tiles away." in caps_examine(P, H), "examine gives the reach")

	var/datum/capability/reach/C = cap_reach(tiles = 0)
	TEST_ASSERT_EQUAL(C.tiles, 1, "reach is at least one tile")

	var/obj/item/cap_fixture/plain = allocate(/obj/item/cap_fixture, T)
	TEST_ASSERT_EQUAL(plain.reach, 1, "without the capability, adjacent only")
