#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_worn_draw_relation
	abstract_type = /datum/unit_test/dq_worn_draw_relation
	var/item_type
	var/worn_slot

/datum/unit_test/dq_worn_draw_relation/saddlebag
	item_type = /obj/item/storage/backpack/saddlebag_common
	worn_slot = SLOT_ID_BACK

/datum/unit_test/dq_worn_draw_relation/avida
	item_type = /obj/item/clothing/head/fluff/avida
	worn_slot = SLOT_ID_HEAD

/datum/unit_test/dq_worn_draw_relation/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, T)
	var/obj/item/I = allocate(item_type, T)
	TEST_ASSERT(I.slot_hooks_enabled(), "Actual concrete item metadata enables its ledger commit hooks")
	TEST_ASSERT_NULL(actual_wearer(I), "A floor item has no worn-slot wearer")
	if(worn_slot == SLOT_ID_BACK)
		var/datum/sprite_accessory/tail/taur/horse/horse = allocate(/datum/sprite_accessory/tail/taur/horse)
		var/datum/sprite_accessory/tail/taur/wolf/wolf = allocate(/datum/sprite_accessory/tail/taur/wolf)
		rel_set(first, nameof(first.tail_style), horse)
		rel_set(second, nameof(second.tail_style), wolf)
	else
		var/datum/sprite_accessory/ears/bnnuy/ears = allocate(/datum/sprite_accessory/ears/bnnuy)
		rel_set(first, nameof(first.ear_style), ears)
		rel_set(first, nameof(first.ear_secondary_style), null)
		rel_set(second, nameof(second.ear_style), null)
		rel_set(second, nameof(second.ear_secondary_style), null)
	TEST_ASSERT(move_into(first, worn_slot, I, first), "Real admission and ledger insertion equip the first wearer")
	TEST_ASSERT_EQUAL(actual_wearer(I), first, "Committed insertion binds the actual wearer")
	TEST_ASSERT_EQUAL(first.get_equipped_item(worn_slot), I, "The real equipment slot contains the item")
	settle_looks()
	if(worn_slot == SLOT_ID_BACK)
		TEST_ASSERT_EQUAL(I.item_state, "saddlebag_horse", "The actual worn draw uses the first wearer's horse sprite")
		var/datum/sprite_accessory/tail/taur/wolf/replacement = allocate(/datum/sprite_accessory/tail/taur/wolf)
		rel_set(first, nameof(first.tail_style), replacement)
		settle_looks()
		TEST_ASSERT_EQUAL(I.item_state, "saddlebag_[replacement.icon_sprite_tag]", "A real style change invalidates the already-worn bag without a manual draw")
	else
		TEST_ASSERT_NOTEQUAL(I.item_state, "avidahatnoears", "The bunny-ear wearer retains the original hat appearance")
		rel_set(first, nameof(first.ear_style), null)
		settle_looks()
		TEST_ASSERT_EQUAL(I.item_state, "avidahatnoears", "Removing the actual ears redraws the already-worn hat without manual hooks or draw calls")
	TEST_ASSERT(first.slot_transfer(I, first, SLOT_ID_HAND_R, first), "Real same-holder reslot moves the worn item into a hand")
	TEST_ASSERT_NULL(actual_wearer(I), "The same human holding the item is not its BACK or HEAD wearer")
	TEST_ASSERT_EQUAL(first.get_equipped_item(SLOT_ID_HAND_R), I, "The hand really contains the reslotted item")
	settle_looks()
	if(worn_slot == SLOT_ID_BACK)
		TEST_ASSERT_EQUAL(I.item_state, "saddlebag", "The unworn bag recovers its original held sprite")
	TEST_ASSERT(first.slot_transfer(I, second, worn_slot, second), "A real cross-holder transfer equips the second wearer")
	TEST_ASSERT_EQUAL(actual_wearer(I), second, "Transfer rebinds the relation to the new wearer")
	TEST_ASSERT_EQUAL(second.get_equipped_item(worn_slot), I, "The new wearer really owns the equipment slot")
	settle_looks()
	if(worn_slot == SLOT_ID_BACK)
		var/datum/sprite_accessory/tail/taur/second_tail = second.tail_style
		TEST_ASSERT_EQUAL(I.item_state, "saddlebag_[second_tail.icon_sprite_tag]", "The transferred bag draws the second wearer's actual style")
	else
		TEST_ASSERT_EQUAL(I.item_state, "avidahatnoears", "The transferred hat draws the second wearer's actual ear policy")
	TEST_ASSERT(second.slot_remove(I, T, second), "The real worn-slot removal drops the item")
	TEST_ASSERT_EQUAL(I.loc, T, "Removal preserves custody on the floor")
	TEST_ASSERT_NULL(actual_wearer(I), "Dropping clears the committed worn-slot relation")
	TEST_ASSERT(move_into(second, worn_slot, I, second), "The dropped item can genuinely be equipped again")
	TEST_ASSERT_EQUAL(actual_wearer(I), second, "Re-equipping rebinds the live relation")
	qdel(second)
	TEST_ASSERT(!QDELETED(I), "The real wearer destroy transaction spills rather than deletes its worn item")
	TEST_ASSERT_NULL(actual_wearer(I), "Wearer teardown clears the item's relation")
	TEST_ASSERT_EQUAL(I.loc, T, "The worn item survives at the wearer's real drop location")
	settle_looks()
	if(worn_slot == SLOT_ID_BACK)
		TEST_ASSERT_EQUAL(I.item_state, "saddlebag", "After wearer deletion the surviving bag draws its unworn sprite")

/datum/unit_test/dq_worn_draw_relation/proc/actual_wearer(obj/item/I)
	if(istype(I, /obj/item/storage/backpack/saddlebag_common))
		var/obj/item/storage/backpack/saddlebag_common/bag = I
		return bag.draw_wearer
	var/obj/item/clothing/head/fluff/avida/hat = I
	return hat.draw_wearer

/datum/unit_test/dq_worn_draw_relation/proc/settle_looks()
	// The wearer changes first; its dependent item look settles on the next drain.
	test_drain()
	test_drain()

#endif
