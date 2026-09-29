// sharp() (code/datums/capabilities/library/sharp.dm), and cap_default_var() (instance vars win).

/obj/item/cap_fixture/blade/capabilities()
	. = ..()
	. += sharp(edge = TRUE)

/obj/item/cap_fixture/spike/capabilities()
	. = ..()
	. += sharp()

/datum/unit_test/dx_cap_sharp

/datum/unit_test/dx_cap_sharp/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/obj/item/cap_fixture/blade/B = allocate(/obj/item/cap_fixture/blade, T)
	TEST_ASSERT(B.sharp, "sharp written at init")
	TEST_ASSERT(B.edge, "edge written at init")
	TEST_ASSERT(is_sharp(B), "is_sharp() reads it")
	TEST_ASSERT(has_edge(B), "has_edge() reads it")
	TEST_ASSERT("It has a keen edge." in B.caps_examine(H), "examine names the edge")

	var/obj/item/cap_fixture/spike/S = allocate(/obj/item/cap_fixture/spike, T)
	TEST_ASSERT(S.sharp, "sharp by default")
	TEST_ASSERT(!S.edge, "no edge by default")
	TEST_ASSERT("It has a sharp point." in S.caps_examine(H), "examine names the point")

	var/obj/item/cap_fixture/plain = allocate(/obj/item/cap_fixture, T)
	TEST_ASSERT(!length(plain.caps_examine(H)), "no capability, no line")

	// A capability's argument is only the type default: an instance that already differs keeps its value.
	plain.reach = 4
	TEST_ASSERT(!cap_default_var(plain, nameof(plain.reach), 2), "an overridden var is left alone")
	TEST_ASSERT_EQUAL(plain.reach, 4, "the instance value wins")
	plain.reach = initial(plain.reach)
	TEST_ASSERT(cap_default_var(plain, nameof(plain.reach), 2), "a var at its compiled default takes the capability's")
	TEST_ASSERT_EQUAL(plain.reach, 2, "written")
