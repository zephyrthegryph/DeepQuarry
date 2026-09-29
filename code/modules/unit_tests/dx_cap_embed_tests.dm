// embed() (code/datums/capabilities/library/embed.dm).

/obj/item/cap_fixture/barbed/capabilities()
	. = ..()
	. += embed(chance = 70)

/obj/item/cap_fixture/slick/capabilities()
	. = ..()
	. += embed(chance = 0)

/datum/unit_test/dx_cap_embed

/datum/unit_test/dx_cap_embed/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/obj/item/cap_fixture/barbed/B = allocate(/obj/item/cap_fixture/barbed, T)
	TEST_ASSERT_EQUAL(B.embed_chance, 70, "the chance is written before Initialize() derives one")
	TEST_ASSERT("It looks like it would lodge in a wound." in B.caps_examine(H), "examine says it lodges")

	var/obj/item/cap_fixture/slick/S = allocate(/obj/item/cap_fixture/slick, T)
	TEST_ASSERT_EQUAL(S.embed_chance, 0, "chance 0 never embeds (not derived from force)")
	TEST_ASSERT(!length(S.caps_examine(H)), "no examine line when it can't embed")

	var/obj/item/cap_fixture/plain = allocate(/obj/item/cap_fixture, T)
	TEST_ASSERT(plain.embed_chance > 0, "without the capability the chance is still derived from force")
