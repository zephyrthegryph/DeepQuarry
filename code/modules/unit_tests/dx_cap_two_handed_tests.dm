// cap_two_handed() (code/datums/capabilities/library/two_handed.dm).

/// Base fixture for item capability tests (the holder is the item).
/obj/item/cap_fixture
	name = "item fixture"
	icon_state = "fixture"
	w_class = ITEMSIZE_NORMAL
	force = 10

/obj/item/cap_fixture/two_handed/capabilities()
	. = ..()
	. += cap_two_handed(force_wielded = 25, icon_base = "axe", log = LOG_GAME)

/obj/item/cap_fixture/two_handed/derived/capabilities()
	. = ..()
	. = without(., /datum/capability/two_handed)
	. += cap_two_handed(multiplier = 2)

/datum/unit_test/dx_cap_two_handed

/datum/unit_test/dx_cap_two_handed/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/cap_fixture/two_handed/A = allocate(/obj/item/cap_fixture/two_handed, T)

	var/datum/interaction/capability/E = dx_cap_entry(A, "Wield")
	TEST_ASSERT_NOTNULL(E, "cap_two_handed() offers its entry")
	TEST_ASSERT_EQUAL(E.entry, INTERACTION_ENTRY_SELF, "a self-use entry")
	TEST_ASSERT_EQUAL(E.display_name(H, A), "Wield", "named for its state")
	TEST_ASSERT_EQUAL(E.why_not(H, A, A), "not in your hand", "wielding needs it in hand")
	TEST_ASSERT("It can be wielded in both hands." in A.caps_examine(H), "examine says it can be wielded")

	TEST_ASSERT(H.put_in_r_hand(A), "the human holds it")
	TEST_ASSERT_NULL(E.why_not(H, A, A), "wieldable with the other hand free")
	TEST_ASSERT(A.attack_self(H), "attack_self runs the entry")
	TEST_ASSERT(cap_has(A, CAP_WIELDED), "wielded")
	TEST_ASSERT_EQUAL(A.force, 25, "force_wielded applies")
	TEST_ASSERT_EQUAL(E.display_name(H, A), "Unwield", "renamed for the new state")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["log"], LOG_GAME, "the declared log level")
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "axe1", "drawn wielded")
	TEST_ASSERT_EQUAL(A.item_state, "axe1", "held sprite wielded")
	TEST_ASSERT("It is held in both hands." in A.caps_examine(H), "examine says wielded")
	var/list/data = list()
	A.caps_ui_data(H, data)
	TEST_ASSERT(data["wielded"], "UI data says wielded")

	TEST_ASSERT(A.attack_self(H), "self-use again unwields")
	TEST_ASSERT(!cap_has(A, CAP_WIELDED), "unwielded")
	TEST_ASSERT_EQUAL(A.force, 10, "the one-handed force is restored")
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "axe0", "drawn unwielded")

	// Filling the other hand unwields, and blocks wielding.
	TEST_ASSERT(A.attack_self(H), "wield again")
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	TEST_ASSERT(H.put_in_l_hand(P), "the other hand takes a pen")
	TEST_ASSERT(!cap_has(A, CAP_WIELDED), "filling the other hand unwields")
	TEST_ASSERT_EQUAL(A.force, 10, "force restored")
	TEST_ASSERT_EQUAL(E.why_not(H, A, A), "you need your other hand free", "refused with the other hand full")
	H.drop_from_inventory(P, T)

	// Dropping unwields.
	TEST_ASSERT(A.attack_self(H), "wield again")
	H.drop_from_inventory(A, T)
	TEST_ASSERT(!cap_has(A, CAP_WIELDED), "dropping unwields")
	TEST_ASSERT_EQUAL(A.force, 10, "force restored on drop")

	// Without force_wielded, the force is derived.
	var/obj/item/cap_fixture/two_handed/derived/D = allocate(/obj/item/cap_fixture/two_handed/derived, T)
	TEST_ASSERT(H.put_in_r_hand(D), "holds the derived one")
	TEST_ASSERT(D.attack_self(H), "wields it")
	TEST_ASSERT_EQUAL(D.force, 20, "one-handed force times the multiplier")
	refresh_flush()
	TEST_ASSERT_EQUAL(D.icon_state, "fixture", "no icon_base: the icon is left alone")
	H.drop_from_inventory(D, T)
