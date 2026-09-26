// Mob inventory on ledger slots (roadmap C3, doc/rewrite/containment.md §6):
// equip, unequip, pickup and drop across slots for humans, simple mobs and
// cyborgs; throwing; restraints; pockets and suit storage through their
// constraints; and a conservation fuzz with a mob as the holder.

/// Checks that `I` is in `M`'s slot `id` and nowhere else, per the ledger.
/datum/unit_test/proc/dq_assert_in_slot(mob/M, obj/item/I, id, label)
	TEST_ASSERT_EQUAL(M.get_equipped_item(id), I, "[label]: [I] should be in [id]")
	TEST_ASSERT_EQUAL(I.loc, M, "[label]: [I] should be inside [M]")
	TEST_ASSERT_EQUAL(M.inventory_slot_id(I), id, "[label]: the ledger should list [I] in [id]")
	dq_verify_ledger(M, label)

// ---- Humans ----

/datum/unit_test/dq_inventory_human_equip_parity

/datum/unit_test/dq_inventory_human_equip_parity/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	// Slot, item type, in wearing order (the ID and pockets need the jumpsuit).
	var/list/cases = list(
		list(slot_w_uniform, SLOT_ID_UNIFORM, /obj/item/clothing/under/color/grey),
		list(slot_wear_suit, SLOT_ID_SUIT, /obj/item/clothing/suit/storage/hazardvest),
		list(slot_back, SLOT_ID_BACK, /obj/item/storage/backpack),
		list(slot_belt, SLOT_ID_BELT, /obj/item/storage/belt/utility),
		list(slot_head, SLOT_ID_HEAD, /obj/item/clothing/head/hardhat),
		list(slot_wear_mask, SLOT_ID_MASK, /obj/item/clothing/mask/breath),
		list(slot_gloves, SLOT_ID_GLOVES, /obj/item/clothing/gloves/black),
		list(slot_shoes, SLOT_ID_SHOES, /obj/item/clothing/shoes/black),
		list(slot_glasses, SLOT_ID_EYES, /obj/item/clothing/glasses/meson),
		list(slot_l_ear, SLOT_ID_EAR_L, /obj/item/radio/headset),
		list(slot_wear_id, SLOT_ID_ID, /obj/item/card/id),
		list(slot_l_store, SLOT_ID_POCKET_L, /obj/item/pen),
		list(slot_r_store, SLOT_ID_POCKET_R, /obj/item/pen),
	)
	var/list/worn = list()
	for(var/list/c as anything in cases)
		var/slot = c[1]
		var/id = c[2]
		var/path = c[3]
		var/obj/item/I = new path(T)
		var/why = I.equip_refusal(H, slot, TRUE)
		TEST_ASSERT_NULL(why, "[path] into [id] was refused: [why]")
		TEST_ASSERT(H.equip_to_slot_if_possible(I, slot, disable_warning = TRUE), "[path] should equip into [id]")
		dq_assert_in_slot(H, I, id, "equip [id]")
		TEST_ASSERT_EQUAL(H.get_inventory_slot(I), slot, "get_inventory_slot for [id]")
		TEST_ASSERT_EQUAL(H.get_equipped_item(slot), I, "the slot_* number reads the same slot as [id]")
		worn[id] = I

	// Occupied slots refuse, and a refused move changes nothing.
	var/obj/item/clothing/head/hardhat/spare = new(T)
	TEST_ASSERT(findtext(spare.equip_refusal(H, slot_head, TRUE), "already wearing"), "a second hat should be refused")
	TEST_ASSERT(!H.equip_to_slot_if_possible(spare, slot_head, disable_warning = TRUE), "a second hat should not equip")
	TEST_ASSERT_EQUAL(spare.loc, T, "a refused hat stays where it was")
	var/obj/item/tool/wrench/W = new(T)
	TEST_ASSERT(W.equip_refusal(H, slot_shoes, TRUE), "a wrench isn't shoes")

	// get_equipped_items(): worn and held, not pockets.
	var/list/items = H.get_equipped_items()
	TEST_ASSERT(worn[SLOT_ID_HEAD] in items, "get_equipped_items lists the hat")
	TEST_ASSERT(!(worn[SLOT_ID_POCKET_L] in items), "get_equipped_items leaves pockets out, as before")

	// Unequip each; taking the jumpsuit off drops the ID and pockets.
	var/obj/item/uniform = worn[SLOT_ID_UNIFORM]
	TEST_ASSERT(H.unEquip(uniform), "the jumpsuit comes off")
	TEST_ASSERT_EQUAL(uniform.loc, T, "the jumpsuit lands on the floor")
	for(var/id in list(SLOT_ID_ID, SLOT_ID_POCKET_L, SLOT_ID_POCKET_R))
		var/obj/item/I = worn[id]
		TEST_ASSERT_NULL(H.get_equipped_item(id), "[id] empties with the jumpsuit")
		TEST_ASSERT_EQUAL(I.loc, T, "[id]'s item falls to the floor")
	for(var/id in list(SLOT_ID_SUIT, SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_HEAD, SLOT_ID_MASK, SLOT_ID_GLOVES, SLOT_ID_SHOES, SLOT_ID_EYES, SLOT_ID_EAR_L))
		var/obj/item/I = worn[id]
		H.drop_from_inventory(I)
		TEST_ASSERT_NULL(H.get_equipped_item(id), "[id] is empty after dropping")
		TEST_ASSERT_EQUAL(I.loc, T, "[id]'s item is on the floor")
		TEST_ASSERT(!(I in H.worn_clothing), "[id]'s item left worn_clothing")
	TEST_ASSERT(!length(H.worn_clothing), "nothing is worn at the end")
	dq_verify_ledger(H, "after unequipping")

/datum/unit_test/dq_inventory_human_pickup_drop

/datum/unit_test/dq_inventory_human_pickup_drop/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/A = new(T)
	var/obj/item/tool/screwdriver/B = new(T)
	var/obj/item/tool/crowbar/C = new(T)
	H.hand = FALSE // right hand active

	TEST_ASSERT(H.put_in_hands(A), "the first item goes in a hand")
	dq_assert_in_slot(H, A, SLOT_ID_HAND_R, "pickup to the active hand")
	TEST_ASSERT_EQUAL(H.get_active_hand(), A, "get_active_hand reads the right hand")
	TEST_ASSERT(H.put_in_hands(B), "the second item goes in the other hand")
	dq_assert_in_slot(H, B, SLOT_ID_HAND_L, "pickup to the inactive hand")
	TEST_ASSERT_EQUAL(H.get_inactive_hand(), B, "get_inactive_hand reads the left hand")
	TEST_ASSERT(!H.put_in_hands(C), "a third item has no hand")
	TEST_ASSERT_EQUAL(C.loc, T, "an item with no free hand lands on the floor")

	// Hand to hand is a move within the mob.
	H.drop_from_inventory(B)
	TEST_ASSERT(H.put_in_l_hand(A), "an item moves from one hand to the other")
	dq_assert_in_slot(H, A, SLOT_ID_HAND_L, "hand to hand")
	TEST_ASSERT_NULL(H.get_right_hand(), "the right hand is empty after the move")

	// Hand to a worn slot and back.
	var/obj/item/storage/belt/utility/belt = new(T)
	TEST_ASSERT(H.put_in_r_hand(belt), "pick up the belt")
	TEST_ASSERT(H.equip_to_slot_if_possible(belt, slot_belt, disable_warning = TRUE), "belt from hand to waist")
	dq_assert_in_slot(H, belt, SLOT_ID_BELT, "hand to belt")
	TEST_ASSERT_NULL(H.get_right_hand(), "the hand is empty once the belt is worn")
	TEST_ASSERT(H.put_in_r_hand(belt), "belt from waist to hand")
	dq_assert_in_slot(H, belt, SLOT_ID_HAND_R, "belt to hand")
	TEST_ASSERT_NULL(H.get_equipped_item(SLOT_ID_BELT), "the belt slot is empty")

	// Drop the active hand.
	H.hand = FALSE
	H.drop_item()
	TEST_ASSERT_EQUAL(belt.loc, T, "drop_item puts the active hand's item on the floor")
	TEST_ASSERT_NULL(H.get_right_hand(), "the dropped hand is empty")

	// temporarilyRemoveItemFromInventory: still inside, in no equip slot.
	TEST_ASSERT(H.temporarilyRemoveItemFromInventory(A), "temporary removal works")
	TEST_ASSERT_EQUAL(A.loc, H, "a temporarily removed item stays inside")
	TEST_ASSERT_NULL(H.inventory_slot_id(A), "a temporarily removed item is in no equip slot")
	TEST_ASSERT_NULL(H.get_left_hand(), "and its hand is empty")
	dq_verify_ledger(H, "after temporary removal")

/// Throwing: the item leaves the hand through the drop path, then flies.
/datum/unit_test/dq_inventory_throw

/datum/unit_test/dq_inventory_throw/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/turf/target = get_step(T, EAST)
	if(!target || target.density)
		target = get_step(T, WEST)
	var/obj/item/tool/wrench/W = new(T)
	H.hand = FALSE
	TEST_ASSERT(H.put_in_r_hand(W), "hold the wrench")
	TEST_ASSERT(H.throw_item(target), "throw it")
	TEST_ASSERT_NULL(H.get_right_hand(), "the thrown item left the hand")
	TEST_ASSERT_NOTEQUAL(W.loc, H, "the thrown item left the mob")
	TEST_ASSERT_NULL(H.inventory_slot_id(W), "the ledger no longer lists it")
	dq_verify_ledger(H, "after throwing")

/// Restraints: handcuffs and legcuffs are slots; cuffing drops what the hands hold.
/datum/unit_test/dq_inventory_cuffs

/datum/unit_test/dq_inventory_cuffs/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/W = new(T)
	H.put_in_hands(W)
	var/obj/item/handcuffs/cuffs = new(T)
	TEST_ASSERT(H.equip_to_slot(cuffs, slot_handcuffed), "cuffs go on")
	dq_assert_in_slot(H, cuffs, SLOT_ID_HANDCUFFED, "handcuffed")
	TEST_ASSERT(H.restrained(), "a cuffed mob is restrained")
	TEST_ASSERT_EQUAL(W.loc, T, "cuffing drops what the hands hold")
	var/obj/item/tool/wrench/W2 = new(T)
	TEST_ASSERT(W2.equip_refusal(H, slot_handcuffed, TRUE), "only handcuffs go on the wrists")
	var/obj/item/handcuffs/second = new(T)
	TEST_ASSERT(!H.equip_to_slot(second, slot_handcuffed), "the wrists take one pair")
	H.drop_from_inventory(cuffs)
	TEST_ASSERT(!H.restrained(), "uncuffed")
	TEST_ASSERT_NULL(H.get_equipped_item(SLOT_ID_HANDCUFFED), "the cuff slot is empty")

	var/obj/item/handcuffs/legcuffs/leg = new(T)
	TEST_ASSERT(H.equip_to_slot(leg, slot_legcuffed), "legcuffs go on")
	dq_assert_in_slot(H, leg, SLOT_ID_LEGCUFFED, "legcuffed")
	TEST_ASSERT(!H.equip_to_slot(new /obj/item/handcuffs(T), slot_legcuffed), "handcuffs don't go on the ankles")
	H.drop_from_inventory(leg)
	TEST_ASSERT_NULL(H.get_equipped_item(SLOT_ID_LEGCUFFED), "the legcuff slot is empty")
	dq_verify_ledger(H, "after cuffs")

/// Pockets and suit storage are slots whose acceptance is the P3 constraints.
/datum/unit_test/dq_inventory_pockets_suit_storage

/datum/unit_test/dq_inventory_pockets_suit_storage/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = new(T)
	var/obj/item/storage/toolbox/toolbox = new(T)
	TEST_ASSERT_EQUAL(pen.equip_refusal(H, slot_l_store, TRUE), "you need a jumpsuit first", "a pocket needs a jumpsuit")
	TEST_ASSERT(!pen.move_into(H, SLOT_ID_POCKET_L, H), "the ledger slot refuses it too")
	TEST_ASSERT_EQUAL(pen.loc, T, "a refused pen stays put")
	var/obj/item/clothing/under/color/grey/U = new(T)
	TEST_ASSERT(H.equip_to_slot_if_possible(U, slot_w_uniform, disable_warning = TRUE), "jumpsuit on")
	TEST_ASSERT_EQUAL(toolbox.equip_refusal(H, slot_l_store, TRUE), "too big for a pocket", "a toolbox is too big")
	TEST_ASSERT(H.equip_to_slot_if_possible(pen, slot_l_store, disable_warning = TRUE), "pen into the pocket")
	dq_assert_in_slot(H, pen, SLOT_ID_POCKET_L, "pocket")

	var/obj/item/pen/other = new(T)
	TEST_ASSERT_EQUAL(other.equip_refusal(H, slot_s_store, TRUE), "you need a suit first", "suit storage needs a suit")
	var/obj/item/clothing/suit/storage/hazardvest/vest = new(T)
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "vest on")
	TEST_ASSERT(H.equip_to_slot_if_possible(other, slot_s_store, disable_warning = TRUE), "a pen fits any suit storage")
	dq_assert_in_slot(H, other, SLOT_ID_SUIT_STORAGE, "suit storage")

	// Taking the suit off drops suit storage; the jumpsuit drops the pockets.
	H.drop_from_inventory(vest)
	TEST_ASSERT_EQUAL(other.loc, T, "suit storage falls with the suit")
	H.drop_from_inventory(U)
	TEST_ASSERT_EQUAL(pen.loc, T, "pockets fall with the jumpsuit")
	dq_verify_ledger(H, "after pockets")

// ---- Simple mobs ----

/datum/unit_test/dq_inventory_simple_mob_hands

/datum/unit_test/dq_inventory_simple_mob_hands/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	var/obj/item/tool/wrench/W = new(T)
	M.has_hands = FALSE
	TEST_ASSERT(!M.put_in_l_hand(W), "a mob without hands can't hold anything")
	TEST_ASSERT_EQUAL(W.loc, T, "the refused item stays on the floor")
	M.has_hands = TRUE
	TEST_ASSERT(M.put_in_l_hand(W), "a handed simple mob holds it")
	dq_assert_in_slot(M, W, SLOT_ID_HAND_L, "simple mob pickup")
	TEST_ASSERT(W.equip_refusal(M, slot_head, TRUE), "a simple mob has no head slot")
	M.drop_l_hand()
	TEST_ASSERT_EQUAL(W.loc, T, "a simple mob drops to the floor")
	TEST_ASSERT_NULL(M.get_left_hand(), "its hand is empty")
	dq_verify_ledger(M, "simple mob")

// ---- Cyborgs ----

/datum/unit_test/dq_inventory_robot_modules

/datum/unit_test/dq_inventory_robot_modules/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	if(!R.module)
		R.module = new /obj/item/robot_module/robot/standard(R)
	var/obj/item/tool = null
	for(var/obj/item/I in R.module.modules)
		tool = I
		break
	TEST_ASSERT_NOTNULL(tool, "the standard module has tools")
	R.activate_module(tool)
	var/slot = R.module_slot_of(tool)
	TEST_ASSERT(slot, "an activated tool is in a module slot")
	dq_assert_in_slot(R, tool, SLOT_ID_MODULE(slot), "module activation")
	R.select_module(slot)
	TEST_ASSERT_EQUAL(R.module_active, tool, "the slot is selected")
	TEST_ASSERT(tool in R.get_all_held_items(), "active modules count as held")
	R.uneq_active()
	TEST_ASSERT_EQUAL(tool.loc, R.module, "deactivating returns the tool to the module")
	TEST_ASSERT_NULL(R.module_active, "nothing is selected")
	TEST_ASSERT_NULL(R.get_module_slot(slot), "the slot is empty")

	// A move that bypasses the robot's procs still clears the selection.
	R.activate_module(tool)
	slot = R.module_slot_of(tool)
	R.select_module(slot)
	tool.forceMove(R.module)
	TEST_ASSERT_NULL(R.module_active, "the slot signal clears the selection")
	TEST_ASSERT_NULL(R.get_module_slot(slot), "and the slot")
	dq_verify_ledger(R, "robot")

// ---- Conservation fuzz ----

/// C1's conservation checks, with a human as the holder: random pickups,
/// equips, unequips, transfers and raw moves; after every step the ledger
/// matches the mob's contents, every item is listed once, and each equip slot
/// holds at most one item.
/datum/unit_test/dq_inventory_conservation_fuzz

/datum/unit_test/dq_inventory_conservation_fuzz/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/paths = list(
		/obj/item/clothing/under/color/grey,
		/obj/item/clothing/suit/storage/hazardvest,
		/obj/item/clothing/head/hardhat,
		/obj/item/clothing/gloves/black,
		/obj/item/clothing/shoes/black,
		/obj/item/clothing/mask/breath,
		/obj/item/storage/backpack,
		/obj/item/pen,
		/obj/item/pen,
		/obj/item/tool/wrench,
		/obj/item/tool/screwdriver,
		/obj/item/handcuffs,
	)
	var/list/things = list()
	for(var/path in paths)
		things += allocate(path, T)
	var/list/equip_slots = list(slot_l_hand, slot_r_hand, slot_back, slot_wear_suit, slot_w_uniform, slot_head, slot_gloves, slot_shoes, slot_wear_mask, slot_l_store, slot_r_store, slot_s_store, slot_handcuffed)
	var/moved = 0
	var/refused = 0
	for(var/step in 1 to 300)
		var/obj/item/I = pick(things)
		var/op = pick(30; "equip", 20; "pickup", 15; "drop", 10; "remove_raw", 10; "insert_raw", 10; "temporary", 5; "swap")
		var/atom/before = I.loc
		switch(op)
			if("equip")
				var/slot = pick(equip_slots)
				if(H.equip_to_slot_if_possible(I, slot, disable_warning = TRUE))
					moved++
					if(H.get_equipped_item(slot) != I)
						TEST_FAIL("step [step]: equip reported success but [I] isn't in slot [slot]")
						return
				else
					refused++
			if("pickup")
				if(I.loc != H && H.put_in_hands(I))
					moved++
			if("drop")
				if(I.loc == H)
					H.drop_from_inventory(I)
					if(I.loc == H)
						TEST_FAIL("step [step]: dropped [I] is still inside")
						return
					moved++
			if("remove_raw")
				if(I.loc == H)
					I.forceMove(T)
			if("insert_raw")
				if(I.loc != H)
					I.forceMove(H)
			if("temporary")
				if(H.temporarilyRemoveItemFromInventory(I, TRUE))
					moved++
			if("swap")
				H.swap_hand()
		if(QDELETED(H))
			TEST_FAIL("step [step]: the mob was deleted")
			return
		if(!dq_inventory_fuzz_check(H, things, "step [step] ([op] [I] from [before])"))
			return
	TEST_NOTICE(src, "moves [moved], refused [refused]")
	TEST_ASSERT(moved >= 30, "the fuzz exercised real moves ([moved])")
	TEST_ASSERT(refused >= 5, "the fuzz exercised refusals ([refused])")

/datum/unit_test/dq_inventory_conservation_fuzz/proc/dq_inventory_fuzz_check(mob/living/carbon/human/H, list/things, label)
	if(!dq_verify_ledger(H, label))
		return FALSE
	var/datum/ledger/L = dq_ledger(H)
	for(var/obj/item/I as anything in things)
		if(QDELETED(I))
			continue
		if(!I.loc)
			TEST_FAIL("[label]: [I] was lost to nullspace")
			return FALSE
		var/listed = L.entries[I] ? 1 : 0
		if(listed != (I.loc == H ? 1 : 0))
			TEST_FAIL("[label]: [I] in [I.loc] is listed [listed] times by the mob's ledger")
			return FALSE
		var/id = H.inventory_slot_id(I)
		if(id && H.get_equipped_item(id) != I)
			TEST_FAIL("[label]: [I] is in [id] but the slot reads [H.get_equipped_item(id)]")
			return FALSE
	for(var/datum/om/relation/slot/def as anything in L.defs)
		if(def.capacity_model == SLOT_CAPACITY_COUNT && length(L.slots[def.slot_id]) > def.capacity)
			TEST_FAIL("[label]: [def.slot_id] holds [length(L.slots[def.slot_id])] things")
			return FALSE
	return TRUE
