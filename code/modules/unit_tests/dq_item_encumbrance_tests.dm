#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// Pins how worn and held item slowdown reaches a human's movement delay (human_movement.dm): the worn items' slowdowns add (a positive one scaled by the
// species' item_slowdown_mod, a negative one left alone), a held item counts only when it slows, a pulled item adds its positive slowdown, and the
// whole item tally is scaled by the mod again when it is positive. The expected value is computed here from the raw numbers, so the test holds
// whichever way the item's number is stored.

/obj/item/clothing/suit/dq_test_encumbrance
	name = "encumbering test suit"

/obj/item/clothing/shoes/dq_test_encumbrance
	name = "encumbering test shoes"

/obj/item/dq_test_encumbrance
	name = "encumbering test item"

/obj/item/clothing/shoes/dq_test_encumbrance/heavy
	worn_factors = alist(STAT_ITEM_ENCUMBRANCE = 2.5)

/datum/unit_test/dq_item_encumbrance_default_factor

/datum/unit_test/dq_item_encumbrance_default_factor/Run()
	var/obj/item/clothing/shoes/dq_test_encumbrance/heavy/boots = allocate(/obj/item/clothing/shoes/dq_test_encumbrance/heavy, test_floor())
	TEST_ASSERT_EQUAL(boots.worn_factor(STAT_ITEM_ENCUMBRANCE), 2.5, "an item starts with its type's encumbrance")
	boots.set_worn_factor(STAT_ITEM_ENCUMBRANCE, 4)
	TEST_ASSERT_EQUAL(boots.worn_factor(STAT_ITEM_ENCUMBRANCE), 4, "the factor can be changed")
	TEST_ASSERT_EQUAL(boots.default_worn_factor(STAT_ITEM_ENCUMBRANCE), 2.5, "the type's encumbrance is still known")
	var/obj/item/clothing/shoes/dq_test_encumbrance/heavy/other = allocate(/obj/item/clothing/shoes/dq_test_encumbrance/heavy, test_floor())
	TEST_ASSERT_EQUAL(other.worn_factor(STAT_ITEM_ENCUMBRANCE), 2.5, "changing one item leaves the type's table alone")

/datum/unit_test/dq_item_encumbrance_movement_delay

/// Sets the test item's slowdown through whichever form holds it.
/datum/unit_test/dq_item_encumbrance_movement_delay/proc/set_slow(obj/item/I, value)
	I.set_worn_factor(STAT_ITEM_ENCUMBRANCE, value)

/datum/unit_test/dq_item_encumbrance_movement_delay/proc/expected_tally(mod, list/worn, list/held, pulled)
	var/tally = 0
	for(var/v in worn)
		tally += (v > 0) ? v * mod : v
	for(var/v in held)
		if(v > 0)
			tally += v * mod
	tally += max(pulled, 0)
	if(tally > 0)
		tally *= mod
	return tally

/datum/unit_test/dq_item_encumbrance_movement_delay/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/suit/dq_test_encumbrance/suit = allocate(/obj/item/clothing/suit/dq_test_encumbrance, T)
	var/obj/item/clothing/shoes/dq_test_encumbrance/shoes = allocate(/obj/item/clothing/shoes/dq_test_encumbrance, T)
	var/obj/item/dq_test_encumbrance/held = allocate(/obj/item/dq_test_encumbrance, T)
	var/obj/item/dq_test_encumbrance/drag = allocate(/obj/item/dq_test_encumbrance, T)
	TEST_ASSERT(H.equip_to_slot_if_possible(suit, SLOT_ID_SUIT, quiet = TRUE), "the test suit is worn")
	TEST_ASSERT(H.equip_to_slot_if_possible(shoes, SLOT_ID_SHOES, quiet = TRUE), "the test shoes are worn")
	TEST_ASSERT(H.put_in_active_hand(held), "the test item is held")
	var/species_mod = H.species.item_slowdown_mod
	set_slow(suit, 0)
	set_slow(shoes, 0)
	set_slow(held, 0)
	set_slow(drag, 0)
	var/base = H.movement_delay()
	// suit, shoes, held, pulled
	var/list/cases = list(
		list(2, 1, 0, 0),
		list(2, -1, 0, 0),
		list(0, -1, 0, 0),
		list(0, 0, 3, 0),
		list(0, 0, -2, 0),
		list(1, 0, 2, 0),
		list(1, 0, 0, 2),
		list(3, -2, 1, 2),
	)
	for(var/mod in list(1, 0.5, 1.5))
		H.species.item_slowdown_mod = mod
		for(var/list/c in cases)
			set_slow(suit, c[1])
			set_slow(shoes, c[2])
			set_slow(held, c[3])
			set_slow(drag, c[4])
			H.stop_pulling() // pulling the same thing again would let go of it
			if(c[4])
				H.start_pulling(drag)
				TEST_ASSERT_EQUAL(H.pulling_target(), drag, "the test item is pulled")
			var/want = base + expected_tally(mod, list(c[1], c[2]), list(c[3]), c[4])
			var/got = H.movement_delay()
			if(abs(got - want) > 0.001)
				H.species.item_slowdown_mod = species_mod
				return Fail("mod [mod], suit [c[1]] shoes [c[2]] held [c[3]] pulled [c[4]]: delay [got], expected [want] (naked [base])")
	H.stop_pulling()
	H.species.item_slowdown_mod = species_mod

#endif
