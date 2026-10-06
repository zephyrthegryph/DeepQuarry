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
/obj/item/assembly/mousetrap/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(.)
		return TRUE
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
			return TRUE

		to_chat(user, span_notice("You disarm [src]."))
	armed = !armed
	update_icon()
	play_sfx(user, SFX_WEAPONS_HANDCUFFS)
	return TRUE

/obj/item/assembly/mousetrap/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/mousetrap_hand,
	)
	var/static/list/hide_spec = INTERACT_VERB("Hide", PROC_REF(mousetrap_hide_under_effect))
	into += dq_interaction_from_spec(/obj/item/assembly/mousetrap, hide_spec)
	..()

/// Old attack_hand: trigger it early if armed and the user fumbles; otherwise not handled
/// (falls through the same as it always did — this override never called ..() when armed).
/datum/interaction/entry_hand/mousetrap_hand
	id = "mousetrap_hand"
	name = "Use"
	effect = /obj/item/assembly/mousetrap/proc/interaction_hand

/obj/item/assembly/mousetrap/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(armed)
		if(CLUMSY_FAIL_CHANCE(user))
			var/which_hand = BP_L_HAND
			if(!user.hand)
				which_hand = BP_R_HAND
			triggered(user, which_hand)
			act_message(user, src, MSG_SELF(span_warning("You accidentally trigger %T%!")), \
				MSG_OTHERS(span_warning("%U% accidentally sets off %T%, breaking [p_their()] fingers.")))
			return TRUE
	return FALSE

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

DAMAGE_REACTION(/obj/item/assembly/mousetrap, DAMAGE_THROWN, PROC_REF(mousetrap_thrown_trigger))

/// An armed trap snaps shut on whatever is thrown at it (and takes nothing else from the hit).
/obj/item/assembly/mousetrap/proc/mousetrap_thrown_trigger(datum/damage_packet/packet)
	if(!armed)
		return
	visible_message(span_warning("[src] is triggered by [packet.source]."))
	triggered(null)
	return DAMAGE_REACTION_BLOCK

/obj/item/assembly/mousetrap/armed
	icon_state = "mousetraparmed"
	armed = 1

/obj/item/assembly/mousetrap/proc/mousetrap_hide_under_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.stat)
		return

	layer = HIDING_LAYER
	to_chat(user, span_notice("You hide [src]."))
