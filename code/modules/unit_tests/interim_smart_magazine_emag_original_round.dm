/// The real smart magazine's emag reaction unlocks original-round removal exactly once without generating or destroying ammunition.
/datum/unit_test/interim_smart_magazine_emag_original_round/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/ammo_magazine/smart/magazine = allocate(/obj/item/ammo_magazine/smart, T)
	var/obj/item/ammo_casing/a45/round = allocate(/obj/item/ammo_casing/a45, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	TEST_ASSERT_EQUAL(magazine.ammo_count(), 0, "the actual smart magazine begins without ammunition")
	TEST_ASSERT(!magazine.emagged && !magazine.can_remove_ammo, "the actual intact smart magazine prohibits round removal")
	// Start with one actual owned round; this fixture covers removal permission, not the separate powered production process.
	TEST_ASSERT(move_into(magazine, nameof(magazine.stored_ammo), round), "the actual owned-ammunition accessor installs the original real round")
	TEST_ASSERT_EQUAL(owner_of(round), magazine, "the original real round belongs to the magazine's actual ammunition list")
	TEST_ASSERT(user.put_in_inactive_hand(magazine), "the actor holds the real smart magazine in the removal hand")
	TEST_ASSERT(magazine.magazine_interaction_hand(hand_act(user)) == OP_DECLINE, "actual hand removal refuses while the smart magazine's safety is intact")
	TEST_ASSERT_EQUAL(round.loc, magazine, "intact removal refusal preserves the same original round inside")
	TEST_ASSERT_EQUAL(magazine.ammo_count(), 1, "intact removal refusal preserves exactly one original round")
	TEST_ASSERT(user.put_in_active_hand(card), "the actor holds the actual emag card")
	var/uses_before = card.uses
	TEST_ASSERT(uses_before > 0, "the actual emag card has a usable charge")
	test_click(user, magazine, card)
	TEST_ASSERT(magazine.emagged && magazine.can_remove_ammo, "the actual emag reaction permanently unlocks original-round removal")
	TEST_ASSERT_EQUAL(card.uses, uses_before - 1, "the actual accepted emag spends exactly one card use")
	TEST_ASSERT_EQUAL(magazine.ammo_count(), 1, "the actual emag reaction generates no new ammunition")
	TEST_ASSERT_EQUAL(round.loc, magazine, "the actual emag reaction preserves the original contained round")
	test_click(user, magazine, card)
	TEST_ASSERT_EQUAL(card.uses, uses_before - 1, "the repeated refusal spends no additional card use")
	TEST_ASSERT(user.unEquip(card), "the actor actually clears the card hand before taking the original round")
	TEST_ASSERT(magazine.magazine_interaction_hand(hand_act(user)) == OP_OK, "the actual emagged magazine permits its public hand-removal behavior")
	TEST_ASSERT_EQUAL(user.get_active_hand(), round, "actual unlocked removal returns the exact original round")
	TEST_ASSERT_EQUAL(round.loc, user, "actual unlocked removal restores real inventory containment")
	TEST_ASSERT_EQUAL(magazine.ammo_count(), 0, "actual unlocked removal empties the magazine")
	TEST_ASSERT_NULL(owner_of(round), "actual unlocked removal releases the original ammunition ownership stamp")
	qdel(magazine)
	TEST_ASSERT(!QDELETED(round), "the returned original round survives empty-magazine teardown")

/// A bare hand op context of `user`, as the op engine hands a handler (the test drives the handler directly).
/datum/unit_test/interim_smart_magazine_emag_original_round/proc/hand_act(mob/user)
	var/datum/act/op/A = take(/datum/act/op)
	A.actor = user
	return A
