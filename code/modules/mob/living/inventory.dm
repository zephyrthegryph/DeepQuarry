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
	for(var/obj/item/storage/S in contents_of(src))
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
	else if(!move_into(S, null, I, src))
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
		after(src, 0.1 SECONDS, PROC_REF(make_item_drop_sound), with = list(item_dropped))

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

/// Hand membership follows ledger reslots as well as physical enter/exit moves.
READS_AS(/mob/living/proc/item_is_in_hands, OP_KEEP_HAND)

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
	// Reslotting can change hand membership without changing the item's loc.
	op_keep_poke(src, OP_KEEP_HAND)
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
		var/mob/grabbed = G?.grab_target()
		L |= grabbed
		if(mobchain_limit-- > 0)
			grabbed?.ret_grab(L, mobchain_limit) // Recurse! They can update the list. It's the same instance as ours.

	// Righty grab!
	if (istype(get_equipped_item(SLOT_ID_HAND_R), /obj/item/grab))
		var/obj/item/grab/G = get_equipped_item(SLOT_ID_HAND_R)
		var/mob/grabbed = G?.grab_target()
		L |= grabbed
		if(mobchain_limit-- > 0)
			grabbed?.ret_grab(L, mobchain_limit) // Same as lefty!

	// On all but the one not called by us, this will just be ignored. Oh well!
	return L

/mob/living/mode()
	set name = "Activate Held Object"
	set category = VERB_CAT_OBJECT
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
/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). A mob dragged onto its dragger shows them its inventory.
/mob/living/proc/drop_input(datum/act/input/A)
	if(inventory_drop_with_actor(A.actor, A.over))
		return TRUE
	return INPUT_FALLTHROUGH

/mob/living/proc/inventory_drop_with_actor(mob/user, atom/over_object)
	var/mob/living/L = over_object
	if(over_object && over_object.is_incorporeal())
		return TRUE
	if(istype(L) && L != src && L == user && Adjacent(L))
		show_inventory_panel(L)
	return FALSE

/mob/living/proc/show_inventory_panel(mob/user, datum/tgui_state/state)
	if(!inventory_panel_type)
		return FALSE

	if(!inventory_panel)
		rel_set(src, nameof(inventory_panel), new inventory_panel_type(src))
	inventory_panel.tgui_interact(user, custom_state = state)

	return TRUE

/datum/inventory_panel
	var/mob/living/host
	tgui_id = "InventoryPanel"

/datum/inventory_panel/New(mob/living/new_host)
	if(!istype(new_host))
		spent(src)
		return
	rel_set(src, nameof(host), new_host)
	. = ..()

/datum/inventory_panel/tgui_host(mob/user)
	return host.tgui_host()

/datum/inventory_panel/tgui_status(mob/user, datum/tgui_state/state)
	if(!host)
		return STATUS_CLOSE
	if(isAI(user))
		return STATUS_CLOSE
	return ..()

CAPABILITIES(/datum/inventory_panel)
	interface(null, state = nameof(GLOB.tgui_physical_state), window_var = nameof(tgui_id))
	ui_shape(slots = list_of(), internals = any, internalsValid = bool())

/datum/inventory_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host)
		spent(src, user)
		return FALSE
	return TRUE

/datum/inventory_panel/ui_title(mob/user)
	return host.name

/// /datum/inventory_panel's window data.
/datum/inventory_panel/ui_data(datum/act/eval/A)
	var/list/data = list()

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



/datum/inventory_panel/human
	tgui_id = "InventoryPanelHuman"

/datum/inventory_panel/human/New(mob/living/carbon/human/new_host)
	if(!istype(new_host))
		spent(src)
		return
	return ..() // Let our parent assign the host.

CAPABILITIES(/datum/inventory_panel/human)
	op("targetSlot", ui_act("targetSlot", arg("slot", schema_text(4096))), then(PROC_REF(ui_act_targetslot)))
/datum/inventory_panel/human/proc/ui_act_targetslot(datum/act/op/A, slot)
	var/mob/user = A.actor
	var/mob/living/carbon/human/H = host
	H.handle_strip(slot, user)
	return TRUE

/datum/inventory_panel/human/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/inventory)
	)

/// /datum/inventory_panel/human's window data.
/datum/inventory_panel/human/ui_data(datum/act/eval/A)
	var/list/data = list() // We don't inherit TGUI data because humans are soooo different.

	var/mob/living/carbon/human/H = host // Not my fault if this runtimes, a human inventory panel should never be created without a human attached.

	var/obj/item/clothing/under/suit = null
	if(istype(H.get_equipped_item(SLOT_ID_UNIFORM), /obj/item/clothing/under))
		suit = H.get_equipped_item(SLOT_ID_UNIFORM)

	var/list/slots = list()
	for(var/entry in H.species.hud.gear)
		var/list/slot_ref = H.species.hud.gear[entry]
		if((slot_ref["slot"] in list(SLOT_ID_POCKET_L, SLOT_ID_POCKET_R)))
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
			"params" = list("slot" = SLOT_ID_HAND_L),
		))
		UNTYPED_LIST_ADD(specialSlots, list(
			"name" = "Right Hand",
			"item" = H.get_equipped_item(SLOT_ID_HAND_R),
			"icon" = H.get_equipped_item(SLOT_ID_HAND_R) ? icon2base64(icon(H.get_equipped_item(SLOT_ID_HAND_R).icon, H.get_equipped_item(SLOT_ID_HAND_R).icon_state, frame = 1)) : null,
			"act" = "targetSlot",
			"params" = list("slot" = SLOT_ID_HAND_R),
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
		data["handcuffedParams"] = list("slot" = SLOT_ID_HANDCUFFED)

	data["legcuffed"] = FALSE
	if(H.get_equipped_item(SLOT_ID_LEGCUFFED))
		data["legcuffed"] = TRUE
		data["legcuffedParams"] = list("slot" = SLOT_ID_LEGCUFFED)

	data["accessory"] = FALSE
	if(suit && LAZYLEN(suit.accessories))
		data["accessory"] = TRUE

	return data
