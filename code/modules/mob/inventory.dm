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
//   get_equipped_item(id)      the item in slot id (SLOT_ID_*)
//   items_on(zone)             items hung on or covering body zone (BP_*)
//   get_active_hand() / get_inactive_hand() / get_left_hand() / get_right_hand()
//   inventory_slot_id(I)       the SLOT_ID_* id I is equipped in, or null
//   get_equipped_items()       worn and held items
//
// Which slots a mob has is its body plan's (code/modules/body/slots.dm). Icon and HUD
// updates follow the slot signals (on_slot_changed), so a move that bypasses
// these procs still leaves the mob consistent.

//The list of slots by priority. equip_to_appropriate_slot() uses this list. Doesn't matter if a mob type doesn't have a slot.
GLOBAL_LIST_INIT(slot_equipment_priority, list(
		SLOT_ID_BACK,
		SLOT_ID_ID,
		SLOT_ID_UNIFORM,
		SLOT_ID_SUIT,
		SLOT_ID_MASK,
		SLOT_ID_HEAD,
		SLOT_ID_SHOES,
		SLOT_ID_GLOVES,
		SLOT_ID_EAR_L,
		SLOT_ID_EAR_R,
		SLOT_ID_EYES,
		SLOT_ID_BELT,
		SLOT_ID_SUIT_STORAGE,
		SLOT_ID_TIE,
		SLOT_ID_POCKET_L,
		SLOT_ID_POCKET_R
	))

/// The slots get_equipped_items() reports (worn and held; not pockets, suit
/// storage or restraints, as before).
GLOBAL_LIST_INIT(slot_ids_equipped_items, list(SLOT_ID_BACK, SLOT_ID_HAND_L, SLOT_ID_HAND_R, SLOT_ID_MASK, SLOT_ID_BELT, SLOT_ID_EAR_L, SLOT_ID_EAR_R, SLOT_ID_EYES, SLOT_ID_GLOVES, SLOT_ID_HEAD, SLOT_ID_SHOES, SLOT_ID_ID, SLOT_ID_SUIT, SLOT_ID_UNIFORM))
/// Worn-clothing slots: get_worn_clothing().
GLOBAL_LIST_INIT(slot_ids_worn_clothing, list(SLOT_ID_BACK, SLOT_ID_MASK, SLOT_ID_BELT, SLOT_ID_EYES, SLOT_ID_GLOVES, SLOT_ID_HEAD, SLOT_ID_SHOES, SLOT_ID_SUIT, SLOT_ID_UNIFORM))

/mob
	var/tmp/obj/item/storage/s_active = null // Even ghosts can/should be able to peek into boxes on the ground

// ---- Reading ----

/// The item in equip slot `id` (SLOT_ID_*), or null.
/mob/proc/get_equipped_item(id) as /obj/item
	var/datum/ledger/L = dq_ledger(src)
	var/list/things = L?.slots[id]
	return length(things) ? things[1] : null

/// Items on body zone `zone` (BP_*): every body-slot item whose slot hangs on
/// that part, plus worn items whose coverage includes it.
/mob/proc/items_on(zone)
	. = list()
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return
	var/part_flag = dq_zone_body_part_flag(zone)
	for(var/datum/om/relation/slot/body/def in dq_slot_defs_for(src))
		var/list/things = L.slots[def.slot_id]
		if(!length(things))
			continue
		var/obj/item/I = things[1]
		if((zone in def.required_parts) || (zone in def.any_parts) || (part_flag && (I.body_parts_covered & part_flag)))
			. += I

/// The SLOT_ID_* id `I` is equipped in, or null (not ours, in the interior, or
/// the root body part: parts are not equipment).
/mob/proc/inventory_slot_id(atom/movable/I)
	if(!I || I.loc != src)
		return null
	var/datum/ledger/L = dq_ledger(src)
	var/list/entry = L?.entries[I]
	if(!entry)
		return null
	var/id = entry[LEDGER_E_SLOT]
	return (id == L.default_id || id == SLOT_ID_PART_ROOT) ? null : id

/// Items in the worn-clothing slots, in slot order.
/mob/proc/get_worn_clothing()
	. = list()
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return
	for(var/id in GLOB.slot_ids_worn_clothing)
		var/list/things = L.slots[id]
		if(length(things))
			. += things

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
	var/obj/item/I = get_equipped_item(SLOT_ID_HAND_L)
	if(I)
		. += I
	I = get_equipped_item(SLOT_ID_HAND_R)
	if(I)
		. += I

/mob/proc/isEquipped(obj/item/I)
	if(!I)
		return 0
	return !!inventory_slot_id(I)

/mob/proc/canUnEquip(obj/item/I)
	if(!I) //If there's nothing to drop, the drop is automatically successful.
		return 1
	return I.mob_can_unequip(src, inventory_slot_id(I))

/mob/proc/getBackSlot()
	return SLOT_BACK

// ---- Slot signals ----

/mob/on_slot_changed(slot_id, atom/movable/thing, inserted)
	. = ..()
	if(slot_id == SLOT_ID_BODY || slot_id == SLOT_ID_PART_ROOT || QDELETED(src))
		return
	inventory_slot_changed(slot_id, thing, inserted)

/// An item entered or left equip slot `slot_id`. Runs inside the move, so it
/// only updates this mob's own state (icons, HUD, caches) and must not sleep or
/// move anything. Behaviour that moves other things is in slot_vacated().
/mob/proc/inventory_slot_changed(slot_id, atom/movable/thing, inserted)
	var/datum/om/relation/slot/body/def = dq_ledger(src)?.def_by_id(slot_id)
	if(istype(def) && def.redraw)
		call(src, def.redraw)()

/// An item left equip slot `slot_id` through the inventory procs. What that
/// does to the rest of the inventory (pockets fall out with the jumpsuit, and
/// so on). Override and call the parent.
/mob/proc/slot_vacated(slot_id, obj/item/I)
	var/datum/om/relation/slot/body/def = dq_ledger(src)?.def_by_id(slot_id)
	if(!istype(def))
		return
	for(var/id in def.drops_with)
		var/obj/item/loose = get_equipped_item(id)
		if(loose)
			drop_from_inventory(loose)

/* Inventory manipulation */

/**
 * This proc is called whenever someone clicks an inventory ui slot.
 *
 * Mostly tries to put the item into the slot if possible, or call attack hand
 * on the item in the slot if the users active hand is empty
 */
/mob/proc/attack_ui(slot, params)
	var/obj/item/active_item = get_active_held_item()
	var/obj/item/equipped_item = get_equipped_item(slot)
	var/list/modifiers = params2list(params)

	if(istype(equipped_item))
		// The converted ops of the worn item (its pick-up/removal default, an item used on it) answer first; what no op answers goes on to the legacy chain.
		if(op_resolve_click(src, equipped_item, active_item, GESTURE_CLICK, ORIGIN_CLICK, TRUE))
			return TRUE
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
	if(equip_to_slot_if_possible(W, SLOT_ID_HAND_L, del_on_fail, disable_warning, redraw_mob))
		return 1
	else if(equip_to_slot_if_possible(W, SLOT_ID_HAND_R, del_on_fail, disable_warning, redraw_mob))
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
			spent(W)
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
		if(SLOT_ID_IN_BACKPACK)
			return equip_to_backpack(W)
		if(SLOT_ID_TIE)
			return equip_accessory(W)
	var/id = slot
	if(!istext(id) || !dq_ledger(src)?.def_by_id(id))
		to_chat(src, span_red("You are trying to equip this item to an unsupported inventory slot. How the heck did you manage that? Stop it..."))
		return FALSE
	var/old_id = inventory_slot_id(W)
	//TG calls attempt_insert -> transferItemToLoc -> doUnEquip -> has_unequipped. This is where we do it instead since we don't have storage datums.
	// An item worn over another (gloves over a ring, magboots over shoes) takes it in here.
	has_unequipped(W, TRUE, slot)
	if(QDELETED(W) || !move_into(src, id, W, src))
		return FALSE
	if(old_id && old_id != id)
		slot_vacated(old_id, W)
	equipped_to_slot(W, slot)
	return TRUE

/// After `W` landed in `slot`: the item's equipped() and the slot's effects.
/mob/proc/equipped_to_slot(obj/item/W, slot)
	if(slot != SLOT_ID_HANDCUFFED) // Restraints were never "equipped".
		W.equipped(src, slot)
	W.hud_layerise()
	W.in_inactive_hand(src)
	W.equip_special()
	on_equipment_changed()

/// SLOT_ID_IN_BACKPACK: into the worn backpack's storage.
/mob/proc/equip_to_backpack(obj/item/W)
	var/obj/item/storage/B = get_equipped_item(SLOT_ID_BACK)
	if(!istype(B))
		return FALSE
	if(W.loc == src && !remove_from_mob(W, B))
		return FALSE
	// The backpack's own rules were checked by the SLOT_ID_IN_BACKPACK predicate.
	if(W.loc != B && !move_into(B, null, W, src))
		W.forceMove(B)
	if(W.loc != B)
		return FALSE
	on_equipment_changed()
	return TRUE

/// SLOT_ID_TIE: attached to the first worn clothing that takes it.
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

/// Whether slot `slot` can be reached now to put on or take off `I`: the item
/// in the slot's covered_by slot mustn't cover it (slot definitions, body/slots.dm).
/mob/proc/slot_is_accessible(slot, obj/item/I, mob/user=null)
	var/datum/om/relation/slot/body/def = dq_ledger(src)?.def_by_id(slot)
	if(!istype(def) || !def.covered_by)
		return TRUE
	var/obj/item/covering = get_equipped_item(def.covered_by)
	if(covering && (covering.body_parts_covered & (I.body_parts_covered | def.cover_flags)))
		to_chat(user, span_warning("\The [covering] is in the way."))
		return FALSE
	return TRUE

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

/// Puts `W` in hand slot `id` (SLOT_ID_HAND_L or SLOT_ID_HAND_R): a ledger
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
	if(!move_into(src, id, W, src))
		return FALSE
	if(old_id && old_id != id)
		slot_vacated(old_id, W)
	W.equipped(src, id)
	W.add_fingerprint(src)
	return TRUE

//Puts the item into your l_hand if possible and calls all necessary triggers/updates. returns 1 on success.
/mob/proc/put_in_l_hand(obj/item/W)
	return put_in_hand_slot(W, SLOT_ID_HAND_L)

//Puts the item into your r_hand if possible and calls all necessary triggers/updates. returns 1 on success.
/mob/proc/put_in_r_hand(obj/item/W)
	return put_in_hand_slot(W, SLOT_ID_HAND_R)

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
	if(is_in_hands(I))
		return 1
	if(inventory_slot_id(I))
		remove_from_mob(I)
		return 0
	I.forceMove(drop_location())
	I.reset_plane_and_layer()
	has_unequipped(I, FALSE)
	return 0

/// Whether `I` already sits in one of this mob's hand slots. put_in_hands()
/// is a no-op for it: a replace_with() successor lands in the original's
/// hand before the call sites that used to hand it over get there.
/mob/proc/is_in_hands(obj/item/I)
	var/slot = inventory_slot_id(I)
	return slot == SLOT_ID_HAND_L || slot == SLOT_ID_HAND_R

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
	if(!move_into(src, SLOT_ID_BODY, I, src))
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
	PUBLISH_LEGACY(src, /datum/notice/mob_unequipped_item, item_dropping, target)
	on_equipment_changed()
	return TRUE

/mob/proc/delete_inventory(include_hands)
	for(var/entry in get_equipped_items())
		consume(entry, src)

/mob/relations()
	. = ..()
	. += rel_one(nameof(s_active)) // the storage being viewed, anywhere nearby
