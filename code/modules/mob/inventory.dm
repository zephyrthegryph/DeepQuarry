// Mob inventory on the containment ledger (roadmap C3, doc/rewrite/containment.md §6).
//
// A mob's equipment lives in ledger slots (code/datums/containment/): each
// equip slot is a slot on the mob, keyed SLOT_ID_*, holding at most one item.
// Picking up, equipping, unequipping, dropping and throwing are ledger moves:
// move_into() to put an item in a slot (checked by the slot's acceptance and
// capacity), slot_remove() to take it out. Anything else inside the mob
// (organs, implants, grabbed and stored things) sits in its interior slot.
//
// Reading equipment:
//   get_equipped_item(slot)    the item in a slot (slot_* number or SLOT_ID_* id)
//   get_active_hand() / get_inactive_hand() / get_left_hand() / get_right_hand()
//   get_inventory_slot(I)      the slot_* number I is equipped in, or 0
//   inventory_slot_id(I)       the SLOT_ID_* id I is equipped in, or null
//   get_equipped_items()       worn and held items
//
// Which slots a mob has is declared by slot_def_types() (for now in
// inventory_slots_interim.dm; the body plans take it over). Icon and HUD
// updates follow the slot signals (on_slot_changed), so a move that bypasses
// these procs still leaves the mob consistent.

//The list of slots by priority. equip_to_appropriate_slot() uses this list. Doesn't matter if a mob type doesn't have a slot.
GLOBAL_LIST_INIT(slot_equipment_priority, list(
		slot_back,
		slot_wear_id,
		slot_w_uniform,
		slot_wear_suit,
		slot_wear_mask,
		slot_head,
		slot_shoes,
		slot_gloves,
		slot_l_ear,
		slot_r_ear,
		slot_glasses,
		slot_belt,
		slot_s_store,
		slot_tie,
		slot_l_store,
		slot_r_store
	))

/// slot_* number -> SLOT_ID_* ledger id (null for the action slots).
GLOBAL_LIST_INIT(slot_id_by_num, dq_build_slot_id_table())
/// SLOT_ID_* ledger id -> slot_* number.
GLOBAL_LIST_INIT(slot_num_by_id, dq_build_slot_num_table())
/// The slots get_equipped_items() reports (worn and held; not pockets, suit
/// storage or restraints, as before).
GLOBAL_LIST_INIT(slot_ids_equipped_items, list(SLOT_ID_BACK, SLOT_ID_L_HAND, SLOT_ID_R_HAND, SLOT_ID_WEAR_MASK, SLOT_ID_BELT, SLOT_ID_L_EAR, SLOT_ID_R_EAR, SLOT_ID_GLASSES, SLOT_ID_GLOVES, SLOT_ID_HEAD, SLOT_ID_SHOES, SLOT_ID_WEAR_ID, SLOT_ID_WEAR_SUIT, SLOT_ID_W_UNIFORM))
/// Worn-clothing slots, whose items make up a human's worn_clothing.
GLOBAL_LIST_INIT(slot_ids_worn_clothing, list(SLOT_ID_BACK, SLOT_ID_WEAR_MASK, SLOT_ID_BELT, SLOT_ID_GLASSES, SLOT_ID_GLOVES, SLOT_ID_HEAD, SLOT_ID_SHOES, SLOT_ID_WEAR_SUIT, SLOT_ID_W_UNIFORM))

/proc/dq_build_slot_id_table()
	. = new /list(SLOT_TOTAL)
	.[slot_l_hand] = SLOT_ID_L_HAND
	.[slot_r_hand] = SLOT_ID_R_HAND
	.[slot_back] = SLOT_ID_BACK
	.[slot_belt] = SLOT_ID_BELT
	.[slot_wear_id] = SLOT_ID_WEAR_ID
	.[slot_s_store] = SLOT_ID_S_STORE
	.[slot_l_store] = SLOT_ID_L_STORE
	.[slot_r_store] = SLOT_ID_R_STORE
	.[slot_glasses] = SLOT_ID_GLASSES
	.[slot_wear_mask] = SLOT_ID_WEAR_MASK
	.[slot_gloves] = SLOT_ID_GLOVES
	.[slot_head] = SLOT_ID_HEAD
	.[slot_shoes] = SLOT_ID_SHOES
	.[slot_wear_suit] = SLOT_ID_WEAR_SUIT
	.[slot_w_uniform] = SLOT_ID_W_UNIFORM
	.[slot_l_ear] = SLOT_ID_L_EAR
	.[slot_r_ear] = SLOT_ID_R_EAR
	.[slot_handcuffed] = SLOT_ID_HANDCUFFED
	.[slot_legcuffed] = SLOT_ID_LEGCUFFED

/proc/dq_build_slot_num_table()
	. = list()
	var/list/by_num = dq_build_slot_id_table()
	for(var/num in 1 to length(by_num))
		if(by_num[num])
			.[by_num[num]] = num

/// The ledger id for `slot`: a slot_* number or already a SLOT_ID_* id. Null
/// for action slots (tie, backpack, legs) and nonsense.
/proc/dq_slot_id(slot)
	if(istext(slot))
		return slot
	if(!isnum(slot) || slot < 1 || slot > SLOT_TOTAL)
		return null
	return GLOB.slot_id_by_num[slot]

/// The slot_* number for ledger id `id`, or 0.
/proc/dq_slot_num(id)
	return GLOB.slot_num_by_id[id] || 0

/mob
	var/tmp/obj/item/storage/s_active = null // Even ghosts can/should be able to peek into boxes on the ground

// ---- Reading ----

/// The item in `slot` (a slot_* number or SLOT_ID_* id), or null.
/mob/proc/get_equipped_item(slot) as /obj/item
	var/id = dq_slot_id(slot)
	if(!id)
		return null
	var/datum/ledger/L = dq_ledger(src)
	var/list/things = L?.slots[id]
	return length(things) ? things[1] : null

/// The SLOT_ID_* id `I` is equipped in, or null (not ours, or in the interior).
/mob/proc/inventory_slot_id(atom/movable/I)
	if(!I || I.loc != src)
		return null
	var/datum/ledger/L = dq_ledger(src)
	var/list/entry = L?.entries[I]
	if(!entry)
		return null
	var/id = entry[LEDGER_E_SLOT]
	return id == L.default_id ? null : id

/// The slot_* number `I` is equipped in, or 0.
/mob/proc/get_inventory_slot(obj/item/I)
	var/id = inventory_slot_id(I)
	return id ? dq_slot_num(id) : 0

///Get the item on the mob in the storage slot identified by the id passed in
/mob/proc/get_item_by_slot(slot_id)
	return get_equipped_item(slot_id)

/// Worn and held items.
/mob/proc/get_equipped_items()
	. = list()
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return
	for(var/id in GLOB.slot_ids_equipped_items)
		var/list/things = L.slots[id]
		if(length(things))
			. += things

///Returns the thing we're currently holding
/mob/proc/get_active_held_item() //Currently just a proc for when we do change to /tg/'s item handling.
	return get_active_hand()

//Returns the thing in our active hand
/mob/proc/get_active_hand() as /obj/item

//Returns the thing in our inactive hand
/mob/proc/get_inactive_hand() as /obj/item

// Override for your specific mob's hands or lack thereof.
/mob/proc/is_holding_item_of_type(typepath)
	for(var/obj/item/I as anything in get_all_held_items())
		if(istype(I, typepath))
			return I
	return FALSE

/// Items held in hands.
/mob/proc/get_all_held_items()
	. = list()
	var/obj/item/I = get_equipped_item(SLOT_ID_L_HAND)
	if(I)
		. += I
	I = get_equipped_item(SLOT_ID_R_HAND)
	if(I)
		. += I

/mob/proc/isEquipped(obj/item/I)
	if(!I)
		return 0
	return get_inventory_slot(I) != 0

/mob/proc/canUnEquip(obj/item/I)
	if(!I) //If there's nothing to drop, the drop is automatically successful.
		return 1
	var/slot = get_inventory_slot(I)
	return I.mob_can_unequip(src, slot)

/mob/proc/getBackSlot()
	return SLOT_BACK

// ---- Slot signals ----

/mob/on_slot_changed(slot_id, atom/movable/thing, inserted)
	. = ..()
	if(slot_id == CONTAINER_SLOT_INTERIOR || QDELETED(src))
		return
	inventory_slot_changed(slot_id, thing, inserted)

/// An item entered or left equip slot `slot_id`. Runs inside the move, so it
/// only updates this mob's own state (icons, HUD, caches) and must not sleep or
/// move anything. Behaviour that moves other things is in slot_vacated().
/mob/proc/inventory_slot_changed(slot_id, atom/movable/thing, inserted)
	switch(slot_id)
		if(SLOT_ID_L_HAND)
			update_inv_l_hand()
		if(SLOT_ID_R_HAND)
			update_inv_r_hand()
		if(SLOT_ID_BACK)
			update_inv_back()
		if(SLOT_ID_WEAR_MASK)
			update_inv_wear_mask()
		if(SLOT_ID_HANDCUFFED)
			update_inv_handcuffed()
		if(SLOT_ID_LEGCUFFED)
			update_inv_legcuffed()
		if(SLOT_ID_BELT)
			update_inv_belt()
		if(SLOT_ID_WEAR_ID)
			update_inv_wear_id()
		if(SLOT_ID_GLASSES)
			update_inv_glasses()
		if(SLOT_ID_GLOVES)
			update_inv_gloves()
		if(SLOT_ID_HEAD)
			update_inv_head()
		if(SLOT_ID_SHOES)
			update_inv_shoes()
		if(SLOT_ID_WEAR_SUIT)
			update_inv_wear_suit()
		if(SLOT_ID_W_UNIFORM)
			update_inv_w_uniform()
		if(SLOT_ID_S_STORE)
			update_inv_s_store()
		if(SLOT_ID_L_EAR, SLOT_ID_R_EAR)
			update_inv_ears()

/// An item left equip slot `slot_id` through the inventory procs. What that
/// does to the rest of the inventory (pockets fall out with the jumpsuit, and
/// so on). Override and call the parent.
/mob/proc/slot_vacated(slot_id, obj/item/I)
	return

/* Inventory manipulation */

/**
 * This proc is called whenever someone clicks an inventory ui slot.
 *
 * Mostly tries to put the item into the slot if possible, or call attack hand
 * on the item in the slot if the users active hand is empty
 */
/mob/proc/attack_ui(slot, params)
	var/obj/item/active_item = get_active_held_item()
	var/obj/item/equipped_item = get_item_by_slot(slot)
	var/list/modifiers = params2list(params)

	if(istype(equipped_item))
		if(active_item)
			equipped_item.attackby(active_item, src) //Wearing an item and item in hand.
			return TRUE

		equipped_item.attack_hand(src, modifiers) //Wearing an item w/ no item in hand.
		return TRUE

	if(istype(active_item))
		if(equip_to_slot_if_possible(active_item, slot,0,0,0)) //NOT wearing an item, but DO have item in hand.
			return TRUE

	return FALSE

/mob/proc/put_in_any_hand_if_possible(obj/item/W, del_on_fail = 0, disable_warning = 1, redraw_mob = 1)
	if(equip_to_slot_if_possible(W, slot_l_hand, del_on_fail, disable_warning, redraw_mob))
		return 1
	else if(equip_to_slot_if_possible(W, slot_r_hand, del_on_fail, disable_warning, redraw_mob))
		return 1
	return 0

//This is a SAFE proc. Use this instead of equip_to_slot()!
//set del_on_fail to have it delete W if it fails to equip
//set disable_warning to disable the 'you are unable to equip that' warning.
//unset redraw_mob to prevent the mob from being redrawn at the end.
/mob/proc/equip_to_slot_if_possible(obj/item/W, slot, del_on_fail = 0, disable_warning = 0, redraw_mob = 1, ignore_obstructions = 1)
	if(!W)
		return 0
	if(W.equip_refusal(src, slot, disable_warning, ignore_obstructions) || !equip_to_slot(W, slot, redraw_mob))
		if(del_on_fail)
			qdel(W)
		else if(!disable_warning)
			to_chat(src, span_red("You are unable to equip that.")) //Only print if del_on_fail is false
		return 0
	return 1

/// Moves `W` into `slot`: a ledger move (move_into), so the slot's acceptance
/// and capacity still apply. Callers check equip_refusal() first (or use
/// equip_to_slot_if_possible()). Returns TRUE if W ended up in the slot.
/mob/proc/equip_to_slot(obj/item/W, slot)
	if(!slot || !istype(W))
		return FALSE
	switch(slot)
		if(slot_in_backpack)
			return equip_to_backpack(W)
		if(slot_tie)
			return equip_accessory(W)
	var/id = dq_slot_id(slot)
	if(!id)
		to_chat(src, span_red("You are trying to equip this item to an unsupported inventory slot. How the heck did you manage that? Stop it..."))
		return FALSE
	var/old_id = inventory_slot_id(W)
	//TG calls attempt_insert -> transferItemToLoc -> doUnEquip -> has_unequipped. This is where we do it instead since we don't have storage datums.
	// An item worn over another (gloves over a ring, magboots over shoes) takes it in here.
	has_unequipped(W, TRUE, slot)
	if(QDELETED(W) || !W.move_into(src, id, src))
		return FALSE
	if(old_id && old_id != id)
		slot_vacated(old_id, W)
	equipped_to_slot(W, slot)
	return TRUE

/// After `W` landed in `slot`: the item's equipped() and the slot's effects.
/mob/proc/equipped_to_slot(obj/item/W, slot)
	if(slot != slot_handcuffed) // Restraints were never "equipped".
		W.equipped(src, slot)
	W.hud_layerise()
	W.in_inactive_hand(src)
	W.equip_special()
	on_equipment_changed()

/// slot_in_backpack: into the worn backpack's storage.
/mob/proc/equip_to_backpack(obj/item/W)
	var/obj/item/storage/B = get_equipped_item(SLOT_ID_BACK)
	if(!istype(B))
		return FALSE
	if(W.loc == src && !remove_from_mob(W, B))
		return FALSE
	// The backpack's own rules were checked by the slot_in_backpack predicate.
	if(W.loc != B && !W.move_into(B, null, src))
		W.forceMove(B)
	if(W.loc != B)
		return FALSE
	on_equipment_changed()
	return TRUE

/// slot_tie: attached to the first worn clothing that takes it.
/mob/proc/equip_accessory(obj/item/W)
	if(!istype(W, /obj/item/clothing/accessory))
		return FALSE
	for(var/id in GLOB.slot_ids_worn_clothing)
		var/obj/item/clothing/C = get_equipped_item(id)
		if(istype(C) && C.attempt_attach_accessory(W, src))
			on_equipment_changed()
			return TRUE
	return FALSE

//This is just a commonly used configuration for the equip_to_slot_if_possible() proc, used to equip people when the rounds tarts and when events happen and such.
/mob/proc/equip_to_slot_or_del(obj/item/W, slot, ignore_obstructions = 1)
	return equip_to_slot_if_possible(W, slot, 1, 1, 0, ignore_obstructions)

//hurgh. these feel hacky, but they're the only way I could get the damn thing to work. I guess they could be handy for antag spawners too?
/mob/proc/equip_voidsuit_to_slot_or_del_with_refit(obj/item/clothing/suit/space/void/W, slot, species = SPECIES_HUMAN)
	W.refit_for_species(species)
	return equip_to_slot_if_possible(W, slot, 1, 1, 0)

/mob/proc/equip_voidhelm_to_slot_or_del_with_refit(obj/item/clothing/head/helmet/space/void/W, slot, species = SPECIES_HUMAN)
	W.refit_for_species(species)
	return equip_to_slot_if_possible(W, slot, 1, 1, 0)

//Checks if a given slot can be accessed at this time, either to equip or unequip I
/mob/proc/slot_is_accessible(slot, obj/item/I, mob/user=null)
	return 1

//puts the item "W" into an appropriate slot in a human's inventory
//returns 0 if it cannot, 1 if successful
/mob/proc/equip_to_appropriate_slot(obj/item/W)
	for(var/slot in GLOB.slot_equipment_priority)
		if(equip_to_slot_if_possible(W, slot, del_on_fail=0, disable_warning=1, redraw_mob=1))
			return 1

	return 0

/mob/proc/equip_to_storage(obj/item/newitem, user_initiated = FALSE)
	return 0

/* Hands */

/// Puts `W` in hand slot `id` (SLOT_ID_L_HAND or SLOT_ID_R_HAND): a ledger
/// move, then equipped(). Returns TRUE on success.
/mob/proc/put_in_hand_slot(obj/item/W, id)
	if(!istype(W))
		return FALSE
	if(QDELETED(W))
		if(!(W.item_flags & DROPDEL))
			log_runtime("[src] tried to pick up a qdeleted object [W]")
		return FALSE
	if(get_equipped_item(id))
		return FALSE
	var/old_id = inventory_slot_id(W)
	if(!W.move_into(src, id, src))
		return FALSE
	if(old_id && old_id != id)
		slot_vacated(old_id, W)
	W.equipped(src, dq_slot_num(id))
	W.add_fingerprint(src)
	return TRUE

//Puts the item into your l_hand if possible and calls all necessary triggers/updates. returns 1 on success.
/mob/proc/put_in_l_hand(obj/item/W)
	return put_in_hand_slot(W, SLOT_ID_L_HAND)

//Puts the item into your r_hand if possible and calls all necessary triggers/updates. returns 1 on success.
/mob/proc/put_in_r_hand(obj/item/W)
	return put_in_hand_slot(W, SLOT_ID_R_HAND)

//Puts the item into our active hand if possible. returns 1 on success.
/mob/proc/put_in_active_hand(obj/item/W)
	return 0 // Moved to human procs because only they need to use hands.

//Puts the item into our inactive hand if possible. returns 1 on success.
/mob/proc/put_in_inactive_hand(obj/item/W)
	return 0 // As above.

//Puts the item our active hand if possible. Failing that it tries our inactive hand. Returns 1 on success.
//If both fail it drops it on the floor and returns 0.
//This is probably the main one you need to know :)
/mob/proc/put_in_hands(obj/item/I)
	if(!I)
		return 0
	if(inventory_slot_id(I))
		remove_from_mob(I)
		return 0
	I.forceMove(drop_location())
	I.reset_plane_and_layer()
	has_unequipped(I, FALSE)
	return 0

// ---- Removing ----

// Removes an item from inventory and places it in the target atom.
// If canremove or other conditions need to be checked then use unEquip instead.
/mob/proc/drop_from_inventory(obj/item/W, atom/target)
	if(!W)
		return FALSE
	if(isnull(target) && isdisposalpacket(src.loc))
		return remove_from_mob(W, src.loc)
	return remove_from_mob(W, target)

/// This proc is called after an item has been removed from a mob but before it has been officially deslotted.
/// equipping = true tells the item we are EQUIPPING it.
/mob/proc/has_unequipped(obj/item/item, equipping, slot) //silent = FALSE) //TODO: Add silent some other time.
	SHOULD_CALL_PARENT(TRUE)
	item.dropped(src, equipping, slot) //silent)
	//update_equipment_speed_mods()
	return TRUE

//Drops the item in our left hand
/mob/proc/drop_l_hand(atom/Target)
	return 0

//Drops the item in our right hand
/mob/proc/drop_r_hand(atom/Target)
	return 0

//Drops the item in our active hand. TODO: rename this to drop_active_hand or something
/mob/proc/drop_item(atom/Target)
	return

//This differs from remove_from_mob() in that it checks if the item can be unequipped first.
/mob/proc/unEquip(obj/item/I, force = 0, atom/target) //Force overrides NODROP for things like wizarditis and admin undress.
	if(!(force || canUnEquip(I)))
		return FALSE
	drop_from_inventory(I, target)
	return TRUE

//visibly unequips I but it is NOT MOVED AND REMAINS IN SRC
//item MUST BE FORCEMOVE'D OR QDEL'D
/mob/proc/temporarilyRemoveItemFromInventory(obj/item/I, force = FALSE, idrop = TRUE)
	var/id = inventory_slot_id(I)
	if(!id)
		return FALSE
	if(!force && !canUnEquip(I))
		return FALSE
	// From its equip slot to the interior: still ours, no longer worn or held.
	if(!I.move_into(src, CONTAINER_SLOT_INTERIOR, src))
		return FALSE
	if(client)
		client.screen -= I
	slot_vacated(id, I)
	on_equipment_changed()
	return TRUE

/// Where a dropped item lands: `target`, or where dropInto() would put it.
/mob/proc/inventory_drop_destination(atom/movable/I, atom/target)
	if(target)
		return target
	var/atom/destination = drop_location()
	while(istype(destination))
		var/atom/next = destination.onDropInto(I)
		if(!istype(next) || next == destination)
			return destination
		destination = next
	return null

/// Takes `I` out of this mob to `destination` (null: nullspace) as a ledger
/// move. A destination holder that refuses it still receives it, as before
/// the ledger: callers of the inventory procs have already decided.
/mob/proc/inventory_release(atom/movable/I, atom/destination)
	if(!destination)
		I.moveToNullspace()
		return
	if(I.loc == src && slot_remove(I, destination, src))
		return
	I.forceMove(destination)

//Attemps to remove an object on a mob.
/mob/proc/remove_from_mob(obj/item_dropping, atom/target)
	if(!item_dropping) // Nothing to remove, so we succeed.
		return 1
	var/id = inventory_slot_id(item_dropping)
	if (src.client)
		src.client.screen -= item_dropping
	item_dropping.reset_plane_and_layer()
	item_dropping.screen_loc = null
	if(isitem(item_dropping))
		inventory_release(item_dropping, inventory_drop_destination(item_dropping, target))
		if(id)
			slot_vacated(id, item_dropping)
		has_unequipped(item_dropping, FALSE)
	//SEND_SIGNAL(item_dropping, COMSIG_ITEM_POST_UNEQUIP, item_dropping, target)
	SEND_SIGNAL(src, COMSIG_MOB_UNEQUIPPED_ITEM, item_dropping, target)
	on_equipment_changed()
	return TRUE

/mob/proc/delete_inventory(include_hands)
	for(var/entry in get_equipped_items())
		drop_from_inventory(entry)
		qdel(entry)
