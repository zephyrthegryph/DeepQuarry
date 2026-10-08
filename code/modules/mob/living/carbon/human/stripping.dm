/mob/living/carbon/human/proc/strip_underwear_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/datum/category_group/underwear/UWC = A.answer.value
	var/datum/category_item/underwear/UWI = LAZYACCESS(all_underwear, UWC.name)
	if(!UWI || UWI.name == "None")
		to_chat(user, span_notice("\The [src] does not have [UWC.gender==PLURAL ? "[UWC.display_name]" : "a [UWC.display_name]"]."))
		return
	hide_underwear[UWC.name] = !hide_underwear[UWC.name]
	update_underwear(1)
	act_message(user, src, others = span_danger("%U% [hide_underwear[UWC.name] ? "takes off" : "puts on"] %T%'s [UWC.display_name]."))

MSG_DEF(strip/pockets, null, span_danger("%U% is trying to empty %T%'s pockets!"))
MSG_DEF(strip/splints, null, span_danger("%U% is trying to remove %T%'s splints!"))
MSG_DEF(strip/sensors, null, span_danger("%U% is trying to set %T%'s sensors!"))
MSG_DEF(strip/internals, null, span_danger("%U% is trying to set %T%'s internals!"))

/mob/living/carbon/human/proc/handle_strip(slot_to_strip,mob/living/user)

	if(!slot_to_strip || !istype(user))
		return

	if(user.incapacitated()  || !user.Adjacent(src))
		// strip menu is TGUI now; close via SStgui.
		SStgui.close_uis(src)
		return

	var/obj/item/target_slot = get_equipped_item(slot_to_strip)

	switch(slot_to_strip)
		// Handle things that are part of this interface but not removing/replacing a given item.
		if("pockets")
			perform_op(user, src, "strip_pockets", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)
			return
		if("splints")
			perform_op(user, src, "strip_splints", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)
			return
		if("sensors")
			perform_op(user, src, "strip_sensors", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)
			return
		if("internals")
			perform_op(user, src, "strip_internals", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)
			return
		if("tie")
			if(!strip_tie_target())
				return
			perform_op(user, src, "strip_tie", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)
			return
		if("underwear")
			open_request(src, /datum/prompt/choice, PROC_REF(strip_underwear_chosen), answerer = user, title = "Show/hide underwear", question = "Choose underwear. (Do not do this without OOC permission from the other player)", choices = GLOB.global_underwear.categories, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
			return

	// Are we placing or stripping?
	var/stripping
	var/obj/item/held = user.get_active_hand()
	if(!istype(held) || is_robot_module(held))
		stripping = TRUE
		if(is_robot_module(held) && istype(held, /obj/item/gripper))
			var/obj/item/gripper/G = held
			var/obj/item/wrapped = G.get_wrapped_item()
			if(istype(wrapped))
				stripping = FALSE
	else
		var/obj/item/holder/holder = held
		if(istype(holder) && src == holder.held_mob)
			stripping = TRUE
		else
			var/obj/item/grab/grab = held
			if(istype(grab) && grab?.grab_target() == src)
				stripping = TRUE

	if(stripping)
		if(!istype(target_slot))  // They aren't holding anything valid and there's nothing to remove, why are we even here?
			return
		if(!target_slot.canremove || (target_slot.item_flags & NOSTRIP))
			to_chat(user, span_warning("You cannot remove \the [src]'s [target_slot.name]."))
			return

	// One op per slot ("strip_<slot id>"); whether something is being put on is the held item the op is given.
	if(!(slot_to_strip in strip_slot_ids()))
		return
	perform_op(user, src, "strip_[slot_to_strip]", stripping ? null : held, ORIGIN_SYSTEM, AUTH_PHYSICAL)
	return TRUE

/// The slots the strip menu can work on: each has a "strip_<id>" op in the human's capabilities.
TYPE_TABLE_DECLARE(/mob/living/carbon/human, strip_slots, list(SLOT_ID_HAND_L, SLOT_ID_HAND_R, SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_POCKET_L, SLOT_ID_POCKET_R, SLOT_ID_UNIFORM, SLOT_ID_SUIT, SLOT_ID_SUIT_STORAGE, SLOT_ID_HEAD, SLOT_ID_MASK, SLOT_ID_EYES, SLOT_ID_EAR_L, SLOT_ID_EAR_R, SLOT_ID_GLOVES, SLOT_ID_SHOES, SLOT_ID_ID, SLOT_ID_HANDCUFFED, SLOT_ID_LEGCUFFED))

/mob/living/carbon/human/proc/strip_slot_ids()
	return TYPE_TABLE_GET(src, strip_slots)

/// The slot a "strip_<slot id>" op works on.
/mob/living/carbon/human/proc/strip_op_slot(datum/act/op/A)
	return copytext(A.oplan.key, 7)

/// What the others are shown when the slot job starts.
/mob/living/carbon/human/proc/strip_slot_text(datum/act/op/A)
	var/obj/item/held = A.held
	var/mob/living/user = A.actor
	if(isnull(held))
		var/obj/item/target_slot = get_equipped_item(strip_op_slot(A))
		return msg_text(null, span_danger("%U% is trying to remove %T%'s [target_slot?.name]!"))
	var/obj/item/put = held
	if(istype(held, /obj/item/gripper))
		var/obj/item/gripper/G = held
		put = G.get_wrapped_item()
	if(strip_op_slot(A) == SLOT_ID_MASK && istype(put, /obj/item/grenade))
		return msg_text(null, span_danger("%U% is trying to put \a [put] in %T%'s mouth!"))
	return msg_text(null, span_danger("%U% is trying to put \a [put] on %T%!"))

/mob/living/carbon/human/proc/strip_slot_done(datum/act/op/A)
	var/slot_to_strip = strip_op_slot(A)
	var/mob/living/user = A.actor
	var/obj/item/held = A.held

	if(isnull(held))
		var/obj/item/target_slot = get_equipped_item(slot_to_strip)
		if(!istype(target_slot))
			return
		add_attack_logs(user,src,"Removed equipment from slot [target_slot]")
		unEquip(target_slot)
		return

	if(user.get_active_hand() != held)
		return
	var/obj/item/holder/mobheld = held
	if(istype(mobheld)&&mobheld.held_mob==src)
		to_chat(user, span_warning("You can't put someone on themselves! Stop trying to break reality!"))
		return

	if(is_robot_module(held) && istype(held, /obj/item/gripper))
		var/obj/item/gripper/G = held
		var/obj/item/wrapped = G.get_wrapped_item()
		if(istype(wrapped))
			if(equip_to_slot_if_possible(wrapped, slot_to_strip, 0, 1, 1))
				if(wrapped.loc != src)
					return
				G.clear_and_select_item()
	else if(user.unEquip(held))
		equip_to_slot_if_possible(held, slot_to_strip, 0, 1, 1)
		if(held.loc != src)
			user.put_in_hands(held)

/mob/living/carbon/human/proc/strip_pockets_done(datum/act/op/A)
	empty_pockets(A.actor)

/mob/living/carbon/human/proc/strip_splints_done(datum/act/op/A)
	remove_splints(A.actor)

/mob/living/carbon/human/proc/strip_sensors_done(datum/act/op/A)
	toggle_sensors(A.actor)

/mob/living/carbon/human/proc/strip_internals_done(datum/act/op/A)
	toggle_internals(A.actor)

/// The accessory the tie job takes: the first one on the uniform, or null.
/mob/living/carbon/human/proc/strip_tie_target()
	var/obj/item/clothing/under/suit = get_equipped_item(SLOT_ID_UNIFORM)
	if(!istype(suit) || !LAZYLEN(suit.accessories))
		return null
	var/obj/item/clothing/accessory/A = suit.accessories[1]
	return istype(A) ? A : null

/mob/living/carbon/human/proc/strip_tie_text(datum/act/op/A)
	var/obj/item/clothing/accessory/tie = strip_tie_target()
	return msg_text(null, span_danger("%U% is trying to remove %T%'s [tie?.name]!"))

/mob/living/carbon/human/proc/strip_tie_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/clothing/under/suit = get_equipped_item(SLOT_ID_UNIFORM)
	var/obj/item/clothing/accessory/tie = strip_tie_target()
	if(!istype(suit) || !tie)
		return

	if(istype(tie, /obj/item/clothing/accessory/badge) || istype(tie, /obj/item/clothing/accessory/medal))
		act_message(user, src, others = span_danger("%U% tears off %I% from %T%'s [suit.name]!"), item = tie)
	add_attack_logs(user,src,"Stripped [tie.name] off [suit.name]")
	tie.on_removed(user)
	own_take_member(suit, nameof(suit.accessories), tie)
	update_inv_w_uniform()

// Empty out everything in the target's pockets.
/mob/living/carbon/human/proc/empty_pockets(mob/living/user)
	if(!get_equipped_item(SLOT_ID_POCKET_R) && !get_equipped_item(SLOT_ID_POCKET_L))
		to_chat(user, span_warning("\The [src] has nothing in their pockets."))
		return
	if(get_equipped_item(SLOT_ID_POCKET_R))
		unEquip(get_equipped_item(SLOT_ID_POCKET_R))
	if(get_equipped_item(SLOT_ID_POCKET_L))
		unEquip(get_equipped_item(SLOT_ID_POCKET_L))
	act_message(user, src, others = span_danger("%U% empties %T%'s pockets!"))

// Modify the current target sensor level.
/mob/living/carbon/human/proc/toggle_sensors(mob/living/user)
	var/obj/item/clothing/under/suit = get_equipped_item(SLOT_ID_UNIFORM)
	if(!suit)
		to_chat(user, span_warning("\The [src] is not wearing a suit with sensors."))
		return
	if (suit.has_sensor >= 2)
		to_chat(user, span_warning("\The [src]'s suit sensor controls are locked."))
		return
	add_attack_logs(user,src,"Adjusted suit sensor level")
	suit.set_sensors(user)

// Remove all splints.
/mob/living/carbon/human/proc/remove_splints(mob/living/user)

	var/can_reach_splints = 1
	if(istype(get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit/space))
		var/obj/item/clothing/suit/space/suit = get_equipped_item(SLOT_ID_SUIT)
		if(suit.supporting_limbs && suit.supporting_limbs.len)
			to_chat(user, span_warning("You cannot remove the splints - [src]'s [suit] is supporting some of the breaks."))
			can_reach_splints = 0

	if(can_reach_splints)
		var/removed_splint
		for(var/obj/item/organ/external/o in organs)
			if (o && o.splinted)
				var/obj/item/S = o.splinted
				if(istype(S) && S.loc == o) //can only remove splints that are actually worn on the organ (deals with hardsuit splints)
					S.add_fingerprint(user)
					if(o.remove_splint())
						user.put_in_active_hand(S)
						removed_splint = 1
		if(removed_splint)
			act_message(user, src, others = span_danger("%U% removes %T%'s splints!"))
		else
			to_chat(user, span_warning("\The [src] has no splints to remove."))

// Set internals on or off.
/mob/living/carbon/human/proc/toggle_internals(mob/living/user)
	if(internal)
		internal.add_fingerprint(user)
		rel_clear(src, nameof(internal))
		if(internals)
			internals.icon_state = "internal0"
	else
		// Check for airtight mask/helmet.
		if(!(istype(get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask) || istype(get_equipped_item(SLOT_ID_HEAD), /obj/item/clothing/head/helmet/space)))
			return
		// Find an internal source.
		if(istype(get_equipped_item(SLOT_ID_BACK), /obj/item/tank))
			rel_set(src, nameof(internal), get_equipped_item(SLOT_ID_BACK))
		else if(istype(get_equipped_item(SLOT_ID_SUIT_STORAGE), /obj/item/tank))
			rel_set(src, nameof(internal), get_equipped_item(SLOT_ID_SUIT_STORAGE))
		else if(istype(get_equipped_item(SLOT_ID_BELT), /obj/item/tank))
			rel_set(src, nameof(internal), get_equipped_item(SLOT_ID_BELT))

	if(internal)
		act_message(src, null, others = span_warning("%U% is now running on internals!"))
		internal.add_fingerprint(user)
		if (internals)
			internals.icon_state = "internal1"
	else
		act_message(user, src, others = span_danger("%U% disables %T%'s internals!"))
