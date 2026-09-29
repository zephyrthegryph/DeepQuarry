// drinkable() (code/datums/capabilities/library/drinkable.dm).

/obj/item/dq_cap_fixture/flask
	flags = OPENCONTAINER

/obj/item/dq_cap_fixture/flask/capabilities()
	. = ..()
	. += drinkable(sip = 4)

/obj/item/dq_cap_fixture/flask/Initialize(mapload)
	. = ..()
	create_reagents(10)
	reagents.add_reagent(REAGENT_ID_SUGAR, 10)

/// Closed: refuses until opened.
/obj/item/dq_cap_fixture/flask/sealed
	flags = NONE

/datum/unit_test/dx_cap_drinkable

/datum/unit_test/dx_cap_drinkable/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_cap_fixture/flask/F = allocate(/obj/item/dq_cap_fixture/flask, T)
	var/obj/item/dq_cap_fixture/flask/sealed/S = allocate(/obj/item/dq_cap_fixture/flask/sealed, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/friend = allocate(/mob/living/carbon/human, T)

	var/datum/interaction/capability/drink = dx_cap_entry(F, "Drink")
	var/datum/interaction/capability/give = dx_cap_entry(F, "Give a drink")
	TEST_ASSERT_NOTNULL(drink, "the Drink entry")
	TEST_ASSERT_EQUAL(drink.entry, INTERACTION_ENTRY_SELF, "using it in hand drinks")
	TEST_ASSERT_NULL(give.default_action, "Give a drink is Menu only")
	TEST_ASSERT_EQUAL(dx_cap_entry(S, "Drink").why_not(H, S, S), "open it first", "a closed container refuses")
	TEST_ASSERT(!length(F.caps_examine(H)), "full: no empty line")

	TEST_ASSERT_EQUAL(cap_drinkable_sip(F, H), 4, "a sip is `sip` units")
	drink.perform(H, F, F)
	TEST_ASSERT_EQUAL(F.reagents.total_volume, 6, "one sip went")
	TEST_ASSERT(H.ingested.get_reagent_amount(REAGENT_ID_SUGAR) > 0, "into the drinker")

	F.cap_drinkable_given(H, friend)
	TEST_ASSERT_EQUAL(F.reagents.total_volume, 2, "the friend took a sip")
	TEST_ASSERT(friend.ingested.get_reagent_amount(REAGENT_ID_SUGAR) > 0, "into the friend")

	drink.perform(H, F, F)
	TEST_ASSERT_EQUAL(F.reagents.total_volume, 0, "the last of it")
	TEST_ASSERT_EQUAL(drink.why_not(H, F, F), "it's empty", "an empty container refuses")
	TEST_ASSERT_EQUAL(give.why_not(H, F, null), "it's empty", "and won't be given")
	TEST_ASSERT_EQUAL(F.caps_examine(H)[1], "It's empty.", "examine says so")
