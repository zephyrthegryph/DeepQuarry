/mob/living
	var/hand = null
	var/obj/item/tank/internal = null//Human/Monkey

/mob/living/equip_to_storage(obj/item/newitem, user_initiated = FALSE)
	// Try put it in their backpack
	var/obj/item/back = get_equipped_item(SLOT_ID_BACK)
	if(istype(back, /obj/item/storage))
		var/obj/item/storage/backpack = back
		if(!backpack.insert_refusal(newitem, user_initiated ? src : null))
			if(user_initiated)
				backpack.handle_item_insertion(newitem)
			else
				store_in(newitem, backpack)
			return back

	// Try to place it in any item that can store stuff, on the mob.
	for(var/obj/item/storage/S in src.contents)
		if(!S.insert_refusal(newitem, user_initiated ? src : null))
			if(user_initiated)
				S.handle_item_insertion(newitem)
			else
				store_in(newitem, S)
			return S

	if(istype(back, /obj/item/rig))	//This would be much cooler if we had componentized storage datums
		var/obj/item/rig/R = back
		if(R.rig_storage)
			var/obj/item/storage/backpack = R.rig_storage
			if(!backpack.insert_refusal(newitem, user_initiated ? src : null))
				if(user_initiated)
					backpack.handle_item_insertion(newitem)
				else
					store_in(newitem, back)
				return backpack
	return 0

/// Puts `I` into storage `S` without the user-facing insertion (no sounds or
/// messages): out of our slots if it is in one, as a ledger move.
/mob/living/proc/store_in(obj/item/I, atom/S)
	if(inventory_slot_id(I))
		remove_from_mob(I, S)
	else if(!I.move_into(S, null, src))
		I.forceMove(S)

//Returns the thing in our active hand
/mob/living/get_active_hand()
	return get_equipped_item(hand ? SLOT_ID_HAND_L : SLOT_ID_HAND_R)

//Returns the thing in our inactive hand
/mob/living/get_inactive_hand()
	return get_equipped_item(hand ? SLOT_ID_HAND_R : SLOT_ID_HAND_L)

//Drops the item in our active hand. TODO: rename this to drop_active_hand or something
/mob/living/drop_item(atom/Target)
	var/obj/item/item_dropped = get_active_hand()

	if (hand)
		. = drop_l_hand(Target)
	else
		. = drop_r_hand(Target)

	if (istype(item_dropped) && !QDELETED(item_dropped) && check_sound_preference(/datum/preference/toggle/drop_sounds))
		addtimer(CALLBACK(src, PROC_REF(make_item_drop_sound), item_dropped), 1)

/mob/proc/make_item_drop_sound(obj/item/I)
	if(QDELETED(I))
		return

	if(I.drop_sound)
		playsound(I, I.drop_sound, 25, 0, preference = /datum/preference/toggle/drop_sounds)


//Drops the item in our left hand
/mob/living/drop_l_hand(atom/Target)
	return drop_from_inventory(get_left_hand(), Target)

//Drops the item in our right hand
/mob/living/drop_r_hand(atom/Target)
	return drop_from_inventory(get_right_hand(), Target)

/mob/living/proc/hands_are_full()
	return (get_right_hand() && get_left_hand())

/mob/living/proc/item_is_in_hands(obj/item/I)
	var/id = inventory_slot_id(I)
	return id == SLOT_ID_HAND_L || id == SLOT_ID_HAND_R

/mob/living/proc/update_held_icons()
	for(var/obj/item/I as anything in get_all_held_items())
		I.update_held_icon()

/mob/living/proc/get_type_in_hands(T)
	var/obj/item/I = get_left_hand()
	if(istype(I, T))
		return I
	I = get_right_hand()
	if(istype(I, T))
		return I
	return null

/mob/living/proc/get_left_hand() as /obj/item
	return get_equipped_item(SLOT_ID_HAND_L)

/mob/living/proc/get_right_hand() as /obj/item
	return get_equipped_item(SLOT_ID_HAND_R)

/mob/living/inventory_slot_changed(slot_id, atom/movable/thing, inserted)
	..()
	// A hand emptied: the other hand's item may stop being two-handed.
	if(!inserted && (slot_id == SLOT_ID_HAND_L || slot_id == SLOT_ID_HAND_R))
		var/obj/item/other = get_equipped_item(slot_id == SLOT_ID_HAND_L ? SLOT_ID_HAND_R : SLOT_ID_HAND_L)
		if(other)
			other.update_twohanding()
			other.update_held_icon()
			update_inv_l_hand()

/mob/living/ret_grab(list/L, mobchain_limit = 5)
	// We're the first!
	if(!L)
		L = list()

	// Lefty grab!
	if (istype(get_equipped_item(SLOT_ID_HAND_L), /obj/item/grab))
		var/obj/item/grab/G = get_equipped_item(SLOT_ID_HAND_L)
		var/mob/grabbed = GRAB_TARGET(G)
		L |= grabbed
		if(mobchain_limit-- > 0)
			grabbed?.ret_grab(L, mobchain_limit) // Recurse! They can update the list. It's the same instance as ours.

	// Righty grab!
	if (istype(get_equipped_item(SLOT_ID_HAND_R), /obj/item/grab))
		var/obj/item/grab/G = get_equipped_item(SLOT_ID_HAND_R)
		var/mob/grabbed = GRAB_TARGET(G)
		L |= grabbed
		if(mobchain_limit-- > 0)
			grabbed?.ret_grab(L, mobchain_limit) // Same as lefty!

	// On all but the one not called by us, this will just be ignored. Oh well!
	return L

/mob/living/mode()
	set name = "Activate Held Object"
	set category = "Object"
	set src = usr

	if(ismecha(loc))
		return

	if(INCAPACITATED_IGNORING(src, INCAPABLE_GRAB))
		return

	if(stat || has_status(EFFECT_PARALYZED) || has_status(EFFECT_STUNNED))
		return

	if(restrained())
		return

	if(!checkClickCooldown())
		return

	setClickCooldown(1)

	var/obj/item/inhand = get_active_hand()
	if(inhand)
		inhand.attack_self(src)
		update_inv_active_hand()
	return

/mob/living/abiotic(full_body = 0)
	if(full_body && ((get_equipped_item(SLOT_ID_HAND_L) && !( get_equipped_item(SLOT_ID_HAND_L).abstract )) || (get_equipped_item(SLOT_ID_HAND_R) && !( get_equipped_item(SLOT_ID_HAND_R).abstract )) || (get_equipped_item(SLOT_ID_BACK) || get_equipped_item(SLOT_ID_MASK))))
		return 1

	if((get_equipped_item(SLOT_ID_HAND_L) && !( get_equipped_item(SLOT_ID_HAND_L).abstract )) || (get_equipped_item(SLOT_ID_HAND_R) && !( get_equipped_item(SLOT_ID_HAND_R).abstract )))
		return 1
	return 0

// This handles the drag-open inventory panel.
/mob/living/MouseDrop(atom/over_object)
	var/mob/living/L = over_object
	if(L.is_incorporeal())
		return
	if(istype(L) && L != src && L == usr && Adjacent(L))
		show_inventory_panel(L)
	. = ..()

/mob/living/proc/show_inventory_panel(mob/user, datum/tgui_state/state)
	if(!inventory_panel_type)
		return FALSE

	if(!inventory_panel)
		inventory_panel = new inventory_panel_type(src)
	inventory_panel.tgui_interact(user, null, state)

	return TRUE

// TGUITODO: Don't forget to Destroy() these properly!
/datum/inventory_panel
	var/mob/living/host
	var/tgui_id = "InventoryPanel"

/datum/inventory_panel/New(mob/living/new_host)
	if(!istype(new_host))
		qdel(src)
		return
	host = new_host
	. = ..()

/datum/inventory_panel/Destroy()
	host = null
	. = ..()

/datum/inventory_panel/tgui_host(mob/user)
	return host.tgui_host()

/datum/inventory_panel/tgui_state(mob/user)
	return GLOB.tgui_physical_state

/datum/inventory_panel/tgui_status(mob/user, datum/tgui_state/state)
	if(!host)
		return STATUS_CLOSE
	if(isAI(user))
		return STATUS_CLOSE
	return ..()

/datum/inventory_panel/tgui_interact(mob/user, datum/tgui/ui, datum/tgui_state/custom_state)
	if(!host)
		qdel(src)
		return
	// This looks kinda complicated, but it's just making sure that the correct state is definitely set
	// before calling open(), so that there isn't any accidental UI closes
	var/open = FALSE
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, tgui_id, host.name)
		open = TRUE
	if(custom_state)
		ui.set_state(custom_state)
	if(open)
		ui.open()
	return ui

/datum/inventory_panel/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	var/list/slots = list()
	slots.Add(list(list(
		"name" = "Head (Mask)",
		"item" = host.get_equipped_item(SLOT_ID_MASK),
		"act" = "mask",
	)))
	slots.Add(list(list(
		"name" = "Left Hand",
		"item" = host.get_equipped_item(SLOT_ID_HAND_L),
		"act" = "l_hand",
	)))
	slots.Add(list(list(
		"name" = "Right Hand",
		"item" = host.get_equipped_item(SLOT_ID_HAND_R),
		"act" = "r_hand",
	)))
	slots.Add(list(list(
		"name" = "Back",
		"item" = host.get_equipped_item(SLOT_ID_BACK),
		"act" = "back",
	)))
	slots.Add(list(list(
		"name" = "Pockets",
		"item" = "Empty Pockets",
		"act" = "pockets",
	)))
	data["slots"] = slots

	data["internals"] = host.internals
	data["internalsValid"] = istype(host.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask) && istype(host.get_equipped_item(SLOT_ID_BACK), /obj/item/tank)

	return data

/datum/inventory_panel/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	// If anyone wants the inventory panel to actually work,
	// add code to handle actions "mask", "l_hand", "r_hand", "back", "pockets", and "internals" here
	// No mobs other than humans actually supported stripping or putting stuff on before the /datum/inventory_panel was
	// created, so feature parity demands not adding that and risking breaking stuff

/datum/inventory_panel/human
	tgui_id = "InventoryPanelHuman"

/datum/inventory_panel/human/New(mob/living/carbon/human/new_host)
	if(!istype(new_host))
		qdel(src)
		return
	return ..() // Let our parent assign the host.

/datum/inventory_panel/human/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	var/mob/living/carbon/human/H = host

	switch(action)
		if("targetSlot")
			H.handle_strip(params["slot"], ui.user)
			return TRUE


/datum/inventory_panel/human/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/inventory)
	)

/datum/inventory_panel/human/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list() // We don't inherit TGUI data because humans are soooo different.

	var/mob/living/carbon/human/H = host // Not my fault if this runtimes, a human inventory panel should never be created without a human attached.

	var/obj/item/clothing/under/suit = null
	if(istype(H.get_equipped_item(SLOT_ID_UNIFORM), /obj/item/clothing/under))
		suit = H.get_equipped_item(SLOT_ID_UNIFORM)

	var/list/slots = list()
	for(var/entry in H.species.hud.gear)
		var/list/slot_ref = H.species.hud.gear[entry]
		if((slot_ref["slot"] in list(slot_l_store, slot_r_store)))
			continue
		var/obj/item/thing_in_slot = H.get_equipped_item(slot_ref["slot"])
		UNTYPED_LIST_ADD(slots, list(
			"name" = slot_ref["name"],
			"item" = thing_in_slot,
			"icon" = thing_in_slot ? icon2base64(icon(thing_in_slot.icon, thing_in_slot.icon_state, frame = 1)) : null,
			"act" = "targetSlot",
			"params" = list("slot" = slot_ref["slot"]),
		))
	data["slots"] = slots

	var/list/specialSlots = list()
	if(H.species.hud.has_hands)
		UNTYPED_LIST_ADD(specialSlots, list(
			"name" = "Left Hand",
			"item" = H.get_equipped_item(SLOT_ID_HAND_L),
			"icon" = H.get_equipped_item(SLOT_ID_HAND_L) ? icon2base64(icon(H.get_equipped_item(SLOT_ID_HAND_L).icon, H.get_equipped_item(SLOT_ID_HAND_L).icon_state, frame = 1)) : null,
			"act" = "targetSlot",
			"params" = list("slot" = slot_l_hand),
		))
		UNTYPED_LIST_ADD(specialSlots, list(
			"name" = "Right Hand",
			"item" = H.get_equipped_item(SLOT_ID_HAND_R),
			"icon" = H.get_equipped_item(SLOT_ID_HAND_R) ? icon2base64(icon(H.get_equipped_item(SLOT_ID_HAND_R).icon, H.get_equipped_item(SLOT_ID_HAND_R).icon_state, frame = 1)) : null,
			"act" = "targetSlot",
			"params" = list("slot" = slot_r_hand),
		))
	data["specialSlots"] = specialSlots

	data["internals"] = H.internals
	data["internalsValid"] = (istype(H.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask) || istype(H.get_equipped_item(SLOT_ID_HEAD), /obj/item/clothing/head/helmet/space)) && (istype(H.get_equipped_item(SLOT_ID_BACK), /obj/item/tank) || istype(H.get_equipped_item(SLOT_ID_BELT), /obj/item/tank) || istype(H.get_equipped_item(SLOT_ID_SUIT_STORAGE), /obj/item/tank))

	data["sensors"] = FALSE
	if(istype(suit) && suit.has_sensor == 1)
		data["sensors"] = TRUE

	data["handcuffed"] = FALSE
	if(H.get_equipped_item(SLOT_ID_HANDCUFFED))
		data["handcuffed"] = TRUE
		data["handcuffedParams"] = list("slot" = slot_handcuffed)

	data["legcuffed"] = FALSE
	if(H.get_equipped_item(SLOT_ID_LEGCUFFED))
		data["legcuffed"] = TRUE
		data["legcuffedParams"] = list("slot" = slot_legcuffed)

	data["accessory"] = FALSE
	if(suit && LAZYLEN(suit.accessories))
		data["accessory"] = TRUE

	return data
