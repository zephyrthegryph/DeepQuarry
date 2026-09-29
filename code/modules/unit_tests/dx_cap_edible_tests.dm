// cap_edible() (code/datums/capabilities/library/edible.dm).

/// Base item fixture for the consumable capabilities (dq_: skipped by the matter snapshot test).
/obj/item/dq_cap_fixture
	name = "item fixture"

/obj/item/dq_cap_fixture/snack/capabilities()
	. = ..()
	. += cap_edible(bites = 3, bite_size = 2, trash = /obj/item/trash/candy)

/obj/item/dq_cap_fixture/snack/Initialize(mapload)
	. = ..()
	create_reagents(10)
	reagents.add_reagent(REAGENT_ID_SUGAR, 10)

/// No reagents: one bite finishes it.
/obj/item/dq_cap_fixture/cracker/capabilities()
	. = ..()
	. += cap_edible()

/datum/unit_test/dx_cap_edible

/datum/unit_test/dx_cap_edible/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_cap_fixture/snack/F = allocate(/obj/item/dq_cap_fixture/snack, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/friend = allocate(/mob/living/carbon/human, T)

	var/datum/interaction/capability/eat = dx_cap_entry(F, "Eat")
	var/datum/interaction/capability/feed = dx_cap_entry(F, "Feed")
	TEST_ASSERT_NOTNULL(eat, "the Eat entry")
	TEST_ASSERT_EQUAL(eat.entry, INTERACTION_ENTRY_SELF, "using it in hand eats")
	TEST_ASSERT_NULL(feed.default_action, "Feed is Menu only")
	TEST_ASSERT(!length(F.caps_examine(H)), "unbitten, no examine line")

	var/before = H.ingested.get_reagent_amount(REAGENT_ID_SUGAR)
	eat.perform(H, F, F)
	TEST_ASSERT_EQUAL(cap_edible_bites_taken(F), 1, "one bite")
	TEST_ASSERT_EQUAL(F.reagents.total_volume, 8, "a bite moves bite_size units")
	TEST_ASSERT(H.ingested.get_reagent_amount(REAGENT_ID_SUGAR) > before, "into the eater's stomach")
	TEST_ASSERT_EQUAL(F.caps_examine(H)[1], span_notice("It was bitten by someone!"), "examine counts the bite")

	// A covered mouth refuses.
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas, T)
	H.equip_to_slot_or_del(mask, SLOT_ID_MASK)
	if(H.check_mouth_coverage())
		TEST_ASSERT_EQUAL(consume_refusal(H, H, F), "\the [mask] is in the way!", "the mask is in the way")
		eat.perform(H, F, F)
		TEST_ASSERT_EQUAL(cap_edible_bites_taken(F), 1, "no bite through a mask")
		H.drop_from_inventory(mask, T)

	// Feeding someone else: the timed action's end takes the bite.
	F.cap_edible_fed(H, friend)
	TEST_ASSERT_EQUAL(cap_edible_bites_taken(F), 2, "the friend took a bite")
	TEST_ASSERT(friend.ingested.get_reagent_amount(REAGENT_ID_SUGAR) > 0, "into the friend's stomach")
	TEST_ASSERT_EQUAL(F.caps_examine(H)[1], span_notice("It was bitten 2 times!"), "examine counts the bites")

	// The last of `bites` finishes it and leaves the trash in hand.
	H.put_in_hands(F)
	eat.perform(H, F, F)
	TEST_ASSERT(QDELETED(F), "eaten up after three bites")
	TEST_ASSERT(locate(/obj/item/trash/candy) in H.get_all_held_items(), "the trash is in the eater's hand")

	var/obj/item/dq_cap_fixture/cracker/C = allocate(/obj/item/dq_cap_fixture/cracker, T)
	var/datum/interaction/capability/eat_cracker = dx_cap_entry(C, "Eat")
	TEST_ASSERT_NULL(eat_cracker.why_not(H, C, C), "a cracker can be eaten")
	TEST_ASSERT(!cap_edible_finished(C), "not yet finished")
	eat_cracker.perform(H, C, C)
	TEST_ASSERT(QDELETED(C), "one bite finishes a reagent-free edible")
