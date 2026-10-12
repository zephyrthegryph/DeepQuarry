// Hand procs for player-controlled SA's
/mob/living/simple_mob/swap_hand()
	set_hand(!hand)
	op_keep_poke(src, OP_KEEP_HAND)
	if(hud_used.l_hand_hud_object && hud_used.r_hand_hud_object)
		if(hand)	//This being 1 means the left hand is in use
			hud_used.l_hand_hud_object.icon_state = "l_hand_active"
			hud_used.r_hand_hud_object.icon_state = "r_hand_inactive"
		else
			hud_used.l_hand_hud_object.icon_state = "l_hand_inactive"
			hud_used.r_hand_hud_object.icon_state = "r_hand_active"
	return

/mob/living/simple_mob/put_in_hands(obj/item/W) // No hands.
	if(has_hands)
		put_in_active_hand(W)
		return 1
	W.forceMove(get_turf(src))
	return 1

//Puts the item into our active hand if possible. returns 1 on success.
/mob/living/simple_mob/put_in_active_hand(obj/item/W)
	if(!has_hands)
		return FALSE
	return (hand ? put_in_l_hand(W) : put_in_r_hand(W))

/// The held sprite of the item in `slot` (SLOT_ID_HAND_L or SLOT_ID_HAND_R), or null. The draw reads the hand slots and watches what they hold.
/mob/living/simple_mob/proc/hand_look(datum/look/look, slot)
	var/obj/item/held = get_equipped_item(slot)
	if(!held)
		return null
	look.watch(held)
	look.watch_look(held)
	var/slot_str = (slot == SLOT_ID_HAND_R) ? slot_r_hand_str : slot_l_hand_str
	//determine icon state to use
	var/t_state
	if(LAZYACCESS(held.item_state_slots, slot_str))
		t_state = held.item_state_slots[slot_str]
	else if(held.item_state)
		t_state = held.item_state
	else
		t_state = held.icon_state
	//determine icon to use
	var/t_icon
	if(LAZYACCESS(held.item_icons, slot_str))
		t_icon = held.item_icons[slot_str]
	else if(held.icon_override)
		t_state += (slot == SLOT_ID_HAND_R) ? "_r" : "_l"
		t_icon = held.icon_override
	else
		t_icon = (slot == SLOT_ID_HAND_R) ? INV_R_HAND_DEF_ICON : INV_L_HAND_DEF_ICON
	return look_overlay_image(t_icon, t_state, color = held.color)

/// A held item sits in its hand's place on the HUD.
/mob/living/simple_mob/inventory_slot_changed(slot_id, atom/movable/thing, inserted)
	..()
	var/obj/item/held = thing
	if(!inserted || !istype(held))
		return
	if(slot_id == SLOT_ID_HAND_R)
		held.screen_loc = ui_rhand
	else if(slot_id == SLOT_ID_HAND_L)
		held.screen_loc = ui_lhand

//Can insert extra huds into the hud holder here.
/mob/living/simple_mob/proc/extra_huds(datum/hud/hud,icon/ui_style,list/hud_elements)
	return

//If they can or cannot use tools/machines/etc
/mob/living/simple_mob/IsAdvancedToolUser()
	return has_hands

/mob/living/simple_mob/proc/IsHumanoidToolUser(atom/tool)
	if(!humanoid_hands)
		var/display_name = null
		if(tool)
			display_name = tool
		else
			display_name = "object"
		to_chat(src, span_danger("Your [hand_form] are not fit for use of \the [display_name]."))
	return humanoid_hands

