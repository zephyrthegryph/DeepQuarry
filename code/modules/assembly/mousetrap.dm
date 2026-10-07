/obj/item/assembly/mousetrap
	name = "mousetrap"
	desc = "A handy little spring-loaded trap for catching pesty rodents."
	icon_state = "mousetrap"
	MATERIAL_BULK(MAT_STEEL, 100)
	var/armed = 0
	special_handling = TRUE


/obj/item/assembly/mousetrap/examine(mob/user)
	. = ..(user)
	if(armed)
		. += "It looks like it's armed."

DECLARE_APPEARANCE_PROC(/obj/item/assembly/mousetrap, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/assembly/mousetrap/appearance_overlays()
	. = list()
	if(armed)
		icon_state = "mousetraparmed"
	else
		icon_state = "mousetrap"
	if(holder())
		holder().update_icon()

/obj/item/assembly/mousetrap/proc/triggered(mob/target, type = "feet")
	if(!armed)
		return
	var/obj/item/organ/external/affecting = null
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		switch(type)
			if("feet")
				if(!H.get_equipped_item(SLOT_ID_SHOES))
					affecting = H.get_organ(pick(BP_L_LEG, BP_R_LEG))
					H.status_at_least(STAT_WEAKENED, 3)
			if(BP_L_HAND, BP_R_HAND)
				if(!H.get_equipped_item(SLOT_ID_GLOVES))
					affecting = H.get_organ(type)
					H.status_at_least(STAT_STUNNED, 3)
		if(affecting)
			H.injure(INJURY_BLUNT, 1, affecting, src)
	else if(ismouse(target))
		var/mob/living/simple_mob/animal/passive/mouse/M = target
		visible_message(span_bolddanger("SPLAT!"))
		M.splat()
	play_sfx(target, SFX_EFFECTS_SNAP)
	layer = MOB_LAYER - 0.2
	armed = 0
	update_icon()
	pulse(0)

/// Overrides assembly's interaction_self(): arm/disarm instead of opening the UI.
/obj/item/assembly/mousetrap/interaction_self(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!armed)
		to_chat(user, span_notice("You arm [src]."))
	else
		if(CLUMSY_FAIL_CHANCE(user))
			var/which_hand = BP_L_HAND
			if(!user.hand)
				which_hand = BP_R_HAND
			triggered(user, which_hand)
			act_message(user, src, MSG_SELF(span_warning("You accidentally trigger %T%!")), \
				MSG_OTHERS(span_warning("%U% accidentally sets off %T%, breaking [p_their()] fingers.")))
			return OP_OK

		to_chat(user, span_notice("You disarm [src]."))
	armed = !armed
	update_icon()
	play_sfx(user, SFX_WEAPONS_HANDCUFFS)
	return OP_OK

CAPABILITIES(/obj/item/assembly/mousetrap)
	extend(/datum/act/hit, instead(then(PROC_REF(mousetrap_thrown_trigger))))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("hide", menu(), label("Hide"), needs(req_adjacent(), req_capable()), then(PROC_REF(mousetrap_hide_under_effect)))

/// Old attack_hand: trigger it early if armed and the user fumbles; otherwise not handled
/// (falls through the same as it always did — this override never called ..() when armed).
/obj/item/assembly/mousetrap/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(armed)
		if(CLUMSY_FAIL_CHANCE(user))
			var/which_hand = BP_L_HAND
			if(!user.hand)
				which_hand = BP_R_HAND
			triggered(user, which_hand)
			act_message(user, src, MSG_SELF(span_warning("You accidentally trigger %T%!")), \
				MSG_OTHERS(span_warning("%U% accidentally sets off %T%, breaking [p_their()] fingers.")))
			return OP_OK
	return OP_DECLINE

/obj/item/assembly/mousetrap/Crossed(atom/movable/AM)
	if(AM.is_incorporeal())
		return
	if(armed)
		if(ishuman(AM))
			var/mob/living/carbon/H = AM
			if(H.m_intent == I_RUN)
				triggered(H)
				act_message(H, src, MSG_SELF(span_warning("You accidentally step on %T%")), MSG_OTHERS(span_warning("%U% accidentally steps on %T%.")))
		if(ismouse(AM))
			triggered(AM)
	..()

/obj/item/assembly/mousetrap/on_found(mob/living/finder)
	if(armed)
		act_message(finder, src, MSG_SELF(span_warning("You accidentally trigger %T%!")), \
			MSG_OTHERS(span_warning("%U% accidentally sets off %T%, breaking [p_their()] fingers.")))
		triggered(finder, finder.hand ? BP_L_HAND : BP_R_HAND)
		return 1	//end the search!
	return 0

/// An armed trap snaps shut on whatever is thrown at it (and takes nothing else from the hit). A thrown thing is the generic hit, so the entry is checked.
/obj/item/assembly/mousetrap/proc/mousetrap_thrown_trigger(datum/act/hit/A)
	var/datum/damage_packet/packet = A.packet
	if(!armed || packet.entry != DAMAGE_ENTRY_THROWN)
		return HOOK_DECLINE
	visible_message(span_warning("[src] is triggered by [packet.source]."))
	triggered(null)
	return OP_OK

/obj/item/assembly/mousetrap/armed
	icon_state = "mousetraparmed"
	armed = 1

/obj/item/assembly/mousetrap/proc/mousetrap_hide_under_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat)
		return OP_DECLINE

	layer = HIDING_LAYER
	to_chat(user, span_notice("You hide [src]."))
	return OP_OK
