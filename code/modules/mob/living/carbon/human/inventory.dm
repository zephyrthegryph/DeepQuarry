/*
Add fingerprints to items when we put them in our hands.
This saves us from having to call add_fingerprint() any time something is put in a human's hands programmatically.
*/

/mob/living/carbon/human/verb/quick_equip()
	set name = "quick-equip"
	set hidden = 1

	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		var/obj/item/I = H.get_active_hand()
		if(!I)
			to_chat(H, span_notice("You are not holding anything to equip."))
			return

		var/moved = FALSE

		// Try an equipment slot
		if(H.equip_to_appropriate_slot(I))
			moved = TRUE

		// No? Try a storage item.
		else if(H.equip_to_storage(I, TRUE))
			moved = TRUE

		// No?! Well, give up.
		if(!moved)
			to_chat(H, span_warning("You are unable to equip that."))

		// Update hand icons
		else
			if(hand)
				update_inv_l_hand(0)
			else
				update_inv_r_hand(0)

/mob/living/carbon/human/equip_to_storage(obj/item/newitem, user_initiated = FALSE)
	// Try put it in their belt first
	var/obj/item/storage/wornbelt = get_equipped_item(SLOT_ID_BELT)
	if(istype(wornbelt))
		if(!wornbelt.insert_refusal(newitem, user_initiated ? src : null))
			if(user_initiated)
				wornbelt.handle_item_insertion(newitem)
			else
				store_in(newitem, wornbelt)
			return wornbelt

	return ..()

/mob/living/carbon/human/proc/equip_in_one_of_slots(obj/item/W, list/slots, del_on_fail = 1)
	for (var/slot in slots)
		if (equip_to_slot_if_possible(W, slots[slot], del_on_fail = 0))
			return slot
	if (del_on_fail)
		qdel(W)
	return null

/mob/living/carbon/human/proc/has_organ(name)
	var/obj/item/organ/external/O = organs_by_name[name]
	return (O && !O.is_stump())

/mob/living/carbon/human/inventory_slot_changed(slot_id, atom/movable/thing, inserted)
	..()
	if(slot_id in GLOB.slot_ids_worn_clothing)
		if(inserted)
			LAZYDISTINCTADD(worn_clothing, thing)
		else
			LAZYREMOVE(worn_clothing, thing)
	var/obj/item/I = thing
	switch(slot_id)
		if(SLOT_ID_HEAD)
			if(istype(I) && (I.flags_inv & (HIDEMASK|BLOCKHAIR|BLOCKHEADHAIR)))
				update_hair(0)	//rebuild hair
				update_inv_ears(0)
				update_inv_wear_mask(0)
			if(inserted && istype(I, /obj/item/clothing/head/kitty))
				I.update_icon(src)
		if(SLOT_ID_MASK)
			if(istype(I) && (I.flags_inv & (BLOCKHAIR|BLOCKHEADHAIR)))
				update_hair(0)	//rebuild hair
				update_inv_ears(0)
			// If this is how the internals are connected, disable them
			if(!inserted && internal && !(get_equipped_item(SLOT_ID_HEAD)?.item_flags & AIRTIGHT))
				if(internals)
					internals.icon_state = "internal0"
				internal = null
		if(SLOT_ID_ID)
			BITSET(hud_updateflag, ID_HUD)
			BITSET(hud_updateflag, WANTED_HUD)

/mob/living/carbon/human/slot_vacated(slot_id, obj/item/I)
	..()
	switch(slot_id)
		if(SLOT_ID_SUIT)
			drop_from_inventory(get_equipped_item(SLOT_ID_SUIT_STORAGE))
		if(SLOT_ID_UNIFORM)
			drop_from_inventory(get_equipped_item(SLOT_ID_POCKET_R))
			drop_from_inventory(get_equipped_item(SLOT_ID_POCKET_L))
			drop_from_inventory(get_equipped_item(SLOT_ID_ID))

/mob/living/carbon/human/equipped_to_slot(obj/item/W, slot)
	..()
	if(slot == slot_l_ear || slot == slot_r_ear)
		equip_offear(W, slot)

/// A two-ear item fills the other ear with a placeholder.
/mob/living/carbon/human/proc/equip_offear(obj/item/W, slot)
	if(!(W.slot_flags & SLOT_TWOEARS) || istype(W, /obj/item/clothing/ears/offear))
		return
	var/other = (slot == slot_l_ear) ? SLOT_ID_EAR_R : SLOT_ID_EAR_L
	if(get_equipped_item(other))
		return
	var/obj/item/clothing/ears/offear/O = new(W)
	// The placeholder isn't worn on its own merits: the ear slot's own rules
	// (a two-ear item needs the other ear free) would refuse it, so it is
	// committed straight into the slot.
	dq_ledger_commit(O, src, other)
	O.hud_layerise()

//Checks if a given slot can be accessed at this time, either to equip or unequip I
/mob/living/carbon/human/slot_is_accessible(slot, obj/item/I, mob/user=null)
	var/obj/item/covering = null
	var/check_flags = 0

	switch(slot)
		if(slot_wear_mask)
			covering = get_equipped_item(SLOT_ID_HEAD)
			check_flags = FACE
		if(slot_glasses)
			covering = get_equipped_item(SLOT_ID_HEAD)
			check_flags = EYES
		if(slot_gloves, slot_w_uniform)
			covering = get_equipped_item(SLOT_ID_SUIT)

	if(covering && (covering.body_parts_covered & (I.body_parts_covered|check_flags)))
		to_chat(user, span_warning("\The [covering] is in the way."))
		return 0
	return 1

/mob/living/carbon/human/proc/drop_all_clothing(remove_underwear = FALSE)
	for(var/obj/item/equipped_thing in worn_clothing)
		if(istype(equipped_thing,/obj/item/clothing/accessory/collar/shock/bluespace))
			continue
		drop_from_inventory(equipped_thing)
	if(remove_underwear)
		for(var/datum/category_group/underwear/UWC in GLOB.global_underwear.categories)
			hide_underwear[UWC.name] = TRUE
		update_underwear(1)
