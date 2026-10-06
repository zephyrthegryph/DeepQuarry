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
			act_message(user, src, others = span_danger("%U% is trying to empty %T%'s pockets!"))
			task_timed(user, HUMAN_STRIP_DELAY, target = src, receiver = src, on_done = PROC_REF(handle_strip_human_done), done_args = list(user))
			return
		if("splints")
			act_message(user, src, others = span_danger("%U% is trying to remove %T%'s splints!"))
			task_timed(user, HUMAN_STRIP_DELAY, target = src, receiver = src, on_done = PROC_REF(handle_strip_human_done2), done_args = list(user))
			return
		if("sensors")
			act_message(user, src, others = span_danger("%U% is trying to set %T%'s sensors!"))
			task_timed(user, HUMAN_STRIP_DELAY, target = src, receiver = src, on_done = PROC_REF(handle_strip_human_done3), done_args = list(user))
			return
		if("internals")
			act_message(user, src, others = span_danger("%U% is trying to set %T%'s internals!"))
			task_timed(user, HUMAN_STRIP_DELAY, target = src, receiver = src, on_done = PROC_REF(handle_strip_human_done4), done_args = list(user))
			return
		if("tie")
			var/obj/item/clothing/under/suit = get_equipped_item(SLOT_ID_UNIFORM)
			if(!istype(suit) || !LAZYLEN(suit.accessories))
				return
			var/obj/item/clothing/accessory/A = suit.accessories[1]
			if(!istype(A))
				return
			act_message(user, src, others = span_danger("%U% is trying to remove %T%'s [A.name]!"))

			task_start(/datum/task/timed/human_handle_strip_human, user, src, receiver = src, duration = HUMAN_STRIP_DELAY, suit = suit, A = A)
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
		act_message(user, src, others = span_danger("%U% is trying to remove %T%'s [target_slot.name]!"))
	else if(!istype(held, /obj/item/gripper))
		if(slot_to_strip == SLOT_ID_MASK && istype(held, /obj/item/grenade))
			act_message(user, src, others = span_danger("%U% is trying to put \a [held] in %T%'s mouth!"))
		else
			act_message(user, src, others = span_danger("%U% is trying to put \a [held] on %T%!"))
	else
		var/obj/item/gripper/G = held
		var/obj/item/wrapped = G.get_wrapped_item()
		if(slot_to_strip == SLOT_ID_MASK && istype(wrapped, /obj/item/grenade))
			act_message(user, src, others = span_danger("%U% is trying to put \a [wrapped] in %T%'s mouth!"))
		else
			act_message(user, src, others = span_danger("%U% is trying to put \a [wrapped] on %T%!"))

	task_start(/datum/task/timed/human_handle_strip_human2, user, src, receiver = src, duration = HUMAN_STRIP_DELAY, slot_to_strip = slot_to_strip, target_slot = target_slot, stripping = stripping, held_arg = held, max_interact_count = 15)
	return TRUE

/mob/living/carbon/human/proc/handle_strip_human_done(mob/living/user)
	empty_pockets(user)
/mob/living/carbon/human/proc/handle_strip_human_done2(mob/living/user)
	remove_splints(user)
/mob/living/carbon/human/proc/handle_strip_human_done3(mob/living/user)
	toggle_sensors(user)
/mob/living/carbon/human/proc/handle_strip_human_done4(mob/living/user)
	toggle_internals(user)
/datum/task/timed/human_handle_strip_human
	complete_proc = /mob/living/carbon/human/proc/handle_strip_human_done5
	var/obj/item/clothing/under/suit
	var/obj/item/clothing/accessory/A

/mob/living/carbon/human/proc/handle_strip_human_done5(datum/task/timed/human_handle_strip_human/task)
	var/mob/living/user = task.actor
	var/obj/item/clothing/under/suit = task.suit
	var/obj/item/clothing/accessory/A = task.A

	if(!A || suit.loc != src || !(A in suit.accessories))
		return

	if(istype(A, /obj/item/clothing/accessory/badge) || istype(A, /obj/item/clothing/accessory/medal))
		act_message(user, src, others = span_danger("%U% tears off %I% from %T%'s [suit.name]!"), item = A)
	add_attack_logs(user,src,"Stripped [A.name] off [suit.name]")
	A.on_removed(user)
	own_take_member(suit, nameof(suit.accessories), A)
	update_inv_w_uniform()
	return
/datum/task/timed/human_handle_strip_human2
	complete_proc = /mob/living/carbon/human/proc/handle_strip_human_done6
	var/slot_to_strip
	var/obj/item/target_slot
	var/stripping
	var/obj/item/held_arg

/mob/living/carbon/human/proc/handle_strip_human_done6(datum/task/timed/human_handle_strip_human2/task)
	var/slot_to_strip = task.slot_to_strip
	var/mob/living/user = task.actor
	var/obj/item/target_slot = task.target_slot
	var/stripping = task.stripping
	var/obj/item/held = task.held_arg

	if(!stripping)
		if(user.get_active_hand() != held)
			return
		var/obj/item/holder/mobheld = held
		if(istype(mobheld)&&mobheld.held_mob==src)
			to_chat(user, span_warning("You can't put someone on themselves! Stop trying to break reality!"))
			return

	if(stripping)
		add_attack_logs(user,src,"Removed equipment from slot [target_slot]")
		unEquip(target_slot)
	else if(is_robot_module(held) && istype(held, /obj/item/gripper))
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
