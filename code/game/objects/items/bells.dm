/obj/item/deskbell
	name = "desk bell"
	desc = "An annoying bell. Ring for service."
	icon = 'icons/obj/items.dmi'
	icon_state = "deskbell"
	force = 2
	throwforce = 2
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 50)
	var/broken
	attack_verb = list("annoyed")
	var/static/radial_examine = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_examine")
	var/static/radial_use = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_use")
	var/static/radial_pickup = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_pickup")

/obj/item/deskbell/examine(mob/user)
	. = ..()
	if(broken)
		. += span_bold("It looks damaged, the ringer is stuck firmly inside.")

/obj/item/deskbell/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!broken)
		play_sfx(src, SFX_EFFECTS_DESKBELL)
	..()

/**
 * Were eight INTERACT_*_AS specs, one per stance for the hand and for an item. The stance is a gesture modifier now: the
 * harm ops answer ACT_ATTACK (a harm click reaches it before ACT_USE), and the ring ops name the stances they answer
 * (an offered requirement: a harm click passes them over). `entry` keeps attack_hand() and attackby() reaching them
 * for their other callers. Each op knows its stance, so each has its own handler.
 */
/obj/item/deskbell/capabilities()
	. = ..()
	. += cap_op("Ring", PROC_REF(ring_by_hand), using = EMPTY_HAND, key = "ring", stance = list(I_HELP, I_DISARM, I_GRAB), entry = INTERACTION_ENTRY_HAND)
	. += cap_op("Hammer rudely", PROC_REF(hammer_by_hand), using = EMPTY_HAND, key = "hammer", action = ACT_ATTACK, stance = I_HURT, entry = INTERACTION_ENTRY_HAND)
	. += cap_op("Ring", PROC_REF(ring_with_item), using = /obj/item, key = "ring_with_item", stance = list(I_HELP, I_DISARM, I_GRAB), entry = INTERACTION_ENTRY_ITEM)
	. += cap_op("Hammer rudely", PROC_REF(hammer_with_item), using = /obj/item, key = "hammer_with_item", action = ACT_ATTACK, stance = I_HURT, entry = INTERACTION_ENTRY_ITEM)

/obj/item/deskbell/proc/ring_by_hand(mob/user)
	return bell_radial(user, I_HELP)

/obj/item/deskbell/proc/hammer_by_hand(mob/user)
	return bell_radial(user, I_HURT)

/obj/item/deskbell/proc/ring_with_item(mob/user, obj/item/held)
	if(!broken)
		ring(user, I_HELP)
	return TRUE

/obj/item/deskbell/proc/hammer_with_item(mob/user, obj/item/held)
	if(!broken)
		ring(user, I_HURT)
	return TRUE

/// The touch: a radial to examine, pick up or ring it (in `stance`: a harm touch hammers).
/obj/item/deskbell/proc/bell_radial(mob/user, stance)

	//This defines the radials and what call we're assiging to them.
	var/list/options = list()
	options["examine"] = radial_examine
	options["pick up"] = radial_pickup
	if(!broken)
		options["use"] = radial_use


	// Just an example, if the bell had no options, due to conditionals, nothing would happen here.
	if(length(options) < 1)
		return TRUE

	// A single available option is answered at once (autopick_single_option); otherwise the player picks.
	open_request(src, /datum/prompt/choice/deskbell, PROC_REF(option_chosen), answerer = user, stance = stance, choices = options, anchor = src, require_near = !issilicon(user))
	return TRUE

/// The bell's radial remembers the stance it was opened in, so "use" rings (or hammers) accordingly.
/datum/prompt/choice/deskbell
	radial = TRUE
	autopick_single_option = TRUE
	timeout = 0
	var/stance = I_HELP

/obj/item/deskbell/proc/option_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/deskbell/request = A.request
	var/mob/user = request.answerer
	if(!user || user.incapacitated())
		return
	// Once the player has decided their option, choose the behaviour that will happen under said option.
	switch(A.answer.value)
		if("examine")
			user.examinate(src)

		if("use")
			if(check_ability(user))
				ring(user, request.stance)
				add_fingerprint(user)

		if("pick up")
			// The standard hand pickup (the item's "Pick up" interaction), with all its checks.
			if(isliving(user) && user.Adjacent(src))
				pick_up_by_hand(user)

/obj/item/deskbell/proc/ring(mob/user, stance = I_HELP)
	if(stance == I_HURT)
		play_sfx(src, SFX_EFFECTS_DESKBELL_RUDE)
		to_chat(user,span_notice("You hammer [src] rudely!"))
		if (prob(2))
			break_bell(user)
	else
		play_sfx(src, SFX_EFFECTS_DESKBELL)
		to_chat(user,span_notice("You gracefully ring [src]."))

/obj/item/deskbell/proc/check_ability(mob/user)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]
		if (H.hand)
			temp = H.organs_by_name[BP_L_HAND]
		if(temp && !temp.is_usable())
			to_chat(H,span_notice("You try to move your [temp.name], but cannot!"))
			return 0
		return 1
	else
		to_chat(user,span_notice("You are not able to ring [src]."))
	return 0

CAPABILITIES(/obj/item/deskbell)
	op("use_wrench", tool(TOOL_WRENCH), needs(req(PROC_REF(on_floor), silent = TRUE)), wait(0.5 SECONDS), then(PROC_REF(wrench_used)))

/// Requirement: the bell lies on a turf (not in a hand or a bag).
/obj/item/deskbell/proc/on_floor(datum/act/op/A)
	return read_once(isturf(loc)) // where the bell lies is asked when the click is made

/obj/item/deskbell/proc/wrench_used(datum/act/op/A)
	to_chat(A.actor, span_notice("You disassemble the desk bell."))
	replace_with(src, /obj/item/stack/material/steel, 1)
	return OP_OK

/obj/item/deskbell/proc/break_bell(mob/user)
	to_chat(user,span_notice("The ringing abruptly stops as [src]'s ringer gets jammed inside!"))
	broken = 1
