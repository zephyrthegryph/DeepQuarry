// The HUD slot boxes (the hands and the body slots) keep their box through every interaction: a click, a pickup, a hand swap and an equip redraw
// the slot objects, and none of those draws may leave a frame in which the box is gone or replaced (the player sees it as a flash).

/// What a player sees of a slot object that matters for its box: the file, the state, whether it shows and how strongly.
/proc/dq_hud_slot_box(atom/movable/screen/inventory/slot)
	return "[slot.icon]|[slot.icon_state]|[slot.alpha]|[slot.invisibility]|[slot.plane]|[slot.layer]|[islist(slot.color) ? "matrix" : slot.color]"

/// Every slot object of `H`'s HUD, with its box signature in `box`: the box and its state may only be the slot's own ones.
/datum/unit_test/dq_hud_slot_box_survives_interaction
	var/list/boxes
	var/list/valid_states

/datum/unit_test/dq_hud_slot_box_survives_interaction/proc/check(list/slots, step)
	for(var/atom/movable/screen/inventory/slot as anything in slots)
		var/now = dq_hud_slot_box(slot)
		var/list/was = boxes[slot]
		if(!(slot.icon_state in valid_states[slot]))
			TEST_FAIL("[slot.name] shows one of its own box states after [step]: [now]")
		if(slot.icon != was["icon"] || slot.alpha != was["alpha"] || slot.invisibility != was["invisibility"] || slot.plane != was["plane"] || slot.layer != was["layer"])
			TEST_FAIL("[slot.name] kept its box through [step]: [was["signature"]] became [now]")

/// Runs the presentation drains one pass at a time, checking the boxes between every pass: an intermediate frame is a flash.
/datum/unit_test/dq_hud_slot_box_survives_interaction/proc/settle(list/slots, step)
	check(slots, "[step] (before the draws)")
	for(var/pass in 1 to 6)
		refresh_drain(null)
		check(slots, "[step] (refresh pass [pass])")
		draw_drain(null)
		check(slots, "[step] (draw pass [pass])")

/datum/unit_test/dq_hud_slot_box_survives_interaction/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	if(!H.hud_used)
		H.set_hud_used(new /datum/hud(H))
		H.hud_used.instantiate()
	refresh_flush()
	var/list/slots = list()
	for(var/atom/movable/screen/inventory/S in H.hud_used.adding + H.hud_used.other)
		slots += S
	TEST_ASSERT(length(slots) >= 4, "the human HUD has its slot objects ([length(slots)])")
	boxes = list()
	valid_states = list()
	for(var/atom/movable/screen/inventory/S as anything in slots)
		boxes[S] = list("alpha" = S.alpha, "icon" = S.icon, "invisibility" = S.invisibility, "plane" = S.plane, "layer" = S.layer, "signature" = dq_hud_slot_box(S))
		var/list/allowed = list(S.icon_state)
		if(S.icon_state == "r_hand_active" || S.icon_state == "r_hand_inactive")
			allowed = list("r_hand_active", "r_hand_inactive")
		else if(S.icon_state == "l_hand_active" || S.icon_state == "l_hand_inactive")
			allowed = list("l_hand_active", "l_hand_inactive")
		valid_states[S] = allowed
	var/obj/item/pen/one = allocate(/obj/item/pen, H.loc)
	var/obj/item/pen/two = allocate(/obj/item/pen, H.loc)
	H.put_in_active_hand(one)
	settle(slots, "picking up")
	H.swap_hand()
	settle(slots, "swapping hands")
	H.put_in_active_hand(two)
	settle(slots, "picking up in the other hand")
	H.swap_hand()
	settle(slots, "swapping back")
	H.drop_from_inventory(one, H.loc)
	settle(slots, "dropping")
	var/obj/item/clothing/mask/breath/mask = allocate(/obj/item/clothing/mask/breath, H.loc)
	H.equip_to_slot_if_possible(mask, SLOT_ID_MASK, quiet = TRUE)
	settle(slots, "equipping a mask")

// Opening a bag and putting something in or taking something out re-lays its HUD: every click catcher is made again, and the segment pictures they carry
// (the box around each stored item) are part of their look. A catcher that waits for the draw queue shows no box until it is drawn, which is a flash.

/datum/unit_test/dq_storage_hud_boxes_are_drawn_when_laid_out

/datum/unit_test/dq_storage_hud_boxes_are_drawn_when_laid_out/proc/boxes_drawn(obj/item/storage/bag, step)
	TEST_ASSERT(bag.hud, "the open bag has its HUD after [step]")
	TEST_ASSERT(length(bag.hud.catchers) >= 1, "the bag shows a catcher per stored item after [step]")
	for(var/atom/movable/storage_slot/SS as anything in bag.hud.catchers)
		TEST_ASSERT(length(SS.overlays) >= 3, "[SS.name] already shows its box segments right after [step], with no drain in between ([length(SS.overlays)] overlays)")
	return TRUE

/datum/unit_test/dq_storage_hud_boxes_are_drawn_when_laid_out/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack, T)
	var/obj/item/pen/one = allocate(/obj/item/pen, T)
	var/obj/item/pen/two = allocate(/obj/item/pen, T)
	bag.show_to(H)
	TEST_ASSERT(bag.handle_item_insertion(one, TRUE), "the first pen goes in")
	if(!boxes_drawn(bag, "the first insert"))
		return
	var/atom/movable/storage_slot/first = bag.hud.catchers[1]
	TEST_ASSERT(bag.handle_item_insertion(two, TRUE), "the second pen goes in")
	if(!boxes_drawn(bag, "the second insert"))
		return
	TEST_ASSERT(first in bag.hud.catchers, "the first pen's catcher is kept when another item goes in, not made again")
	TEST_ASSERT(!QDELETED(first), "and is not deleted")
	var/atom/movable/storage_slot/second = bag.hud.catchers[length(bag.hud.catchers)]
	bag.remove_from_storage(one, T, H)
	TEST_ASSERT(second in bag.hud.catchers, "the other pen's catcher is kept when one comes out")
	boxes_drawn(bag, "a removal")
