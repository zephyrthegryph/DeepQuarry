// Hand procs for player-controlled SA's
/mob/living/simple_mob/swap_hand()
	src.hand = !( src.hand )
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

/mob/living/simple_mob/update_inv_r_hand()
	if(QDESTROYING(src))
		return

	if(get_equipped_item(SLOT_ID_R_HAND))
		get_equipped_item(SLOT_ID_R_HAND).screen_loc = ui_rhand	//TODO

		//determine icon state to use
		var/t_state
		if(LAZYACCESS(get_equipped_item(SLOT_ID_R_HAND).item_state_slots, slot_r_hand_str))
			t_state = get_equipped_item(SLOT_ID_R_HAND).item_state_slots[slot_r_hand_str]
		else if(get_equipped_item(SLOT_ID_R_HAND).item_state)
			t_state = get_equipped_item(SLOT_ID_R_HAND).item_state
		else
			t_state = get_equipped_item(SLOT_ID_R_HAND).icon_state

		//determine icon to use
		var/icon/t_icon
		if(LAZYACCESS(get_equipped_item(SLOT_ID_R_HAND).item_icons, slot_r_hand_str))
			t_icon = get_equipped_item(SLOT_ID_R_HAND).item_icons[slot_r_hand_str]
		else if(get_equipped_item(SLOT_ID_R_HAND).icon_override)
			t_state += "_r"
			t_icon = get_equipped_item(SLOT_ID_R_HAND).icon_override
		else
			t_icon = INV_R_HAND_DEF_ICON

		//apply color
		var/image/standing = image(icon = t_icon, icon_state = t_state)
		standing.color = get_equipped_item(SLOT_ID_R_HAND).color

		r_hand_sprite = standing

	else
		r_hand_sprite = null

	update_icon()

/mob/living/simple_mob/update_inv_l_hand()
	if(QDESTROYING(src))
		return

	if(get_equipped_item(SLOT_ID_L_HAND))
		get_equipped_item(SLOT_ID_L_HAND).screen_loc = ui_lhand	//TODO

		//determine icon state to use
		var/t_state
		if(LAZYACCESS(get_equipped_item(SLOT_ID_L_HAND).item_state_slots, slot_l_hand_str))
			t_state = get_equipped_item(SLOT_ID_L_HAND).item_state_slots[slot_l_hand_str]
		else if(get_equipped_item(SLOT_ID_L_HAND).item_state)
			t_state = get_equipped_item(SLOT_ID_L_HAND).item_state
		else
			t_state = get_equipped_item(SLOT_ID_L_HAND).icon_state

		//determine icon to use
		var/icon/t_icon
		if(LAZYACCESS(get_equipped_item(SLOT_ID_L_HAND).item_icons, slot_l_hand_str))
			t_icon = get_equipped_item(SLOT_ID_L_HAND).item_icons[slot_l_hand_str]
		else if(get_equipped_item(SLOT_ID_L_HAND).icon_override)
			t_state += "_l"
			t_icon = get_equipped_item(SLOT_ID_L_HAND).icon_override
		else
			t_icon = INV_L_HAND_DEF_ICON

		//apply color
		var/image/standing = image(icon = t_icon, icon_state = t_state)
		standing.color = get_equipped_item(SLOT_ID_L_HAND).color

		l_hand_sprite = standing

	else
		l_hand_sprite = null

	update_icon()

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

