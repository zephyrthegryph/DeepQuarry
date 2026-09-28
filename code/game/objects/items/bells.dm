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
		playsound(src, 'sound/effects/deskbell.ogg', 50, 1)
	..()

DECLARE_INTERACTIONS(/obj/item/deskbell, \
	INTERACT_HAND_AS(I_HELP, "Ring", PROC_REF(interaction_hand)), \
	INTERACT_HAND_AS(I_DISARM, "Ring", PROC_REF(interaction_hand)), \
	INTERACT_HAND_AS(I_GRAB, "Ring", PROC_REF(interaction_hand)), \
	INTERACT_HAND_AS(I_HURT, "Hammer rudely", PROC_REF(interaction_hand)), \
	INTERACT_ITEM_AS(I_HELP, "Ring", PROC_REF(interaction_item)), \
	INTERACT_ITEM_AS(I_DISARM, "Ring", PROC_REF(interaction_item)), \
	INTERACT_ITEM_AS(I_GRAB, "Ring", PROC_REF(interaction_item)), \
	INTERACT_ITEM_AS(I_HURT, "Hammer rudely", PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/item/deskbell/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)

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
	om_ask(user, /datum/om/prompt/choice/radial/deskbell, PROC_REF(option_chosen), stance = interaction?.stance || I_HELP, choices = options, anchor = src, require_near = !issilicon(user))
	return TRUE

/// The bell's radial remembers the stance it was opened in, so "use" rings (or hammers) accordingly.
/datum/om/prompt/choice/radial/deskbell
	var/stance = I_HELP

/obj/item/deskbell/proc/option_chosen(datum/om/prompt/choice/radial/deskbell/ask)
	var/mob/user = ask.answerer
	if(!user || user.incapacitated())
		return
	// Once the player has decided their option, choose the behaviour that will happen under said option.
	switch(ask.choice)
		if("examine")
			user.examinate(src)

		if("use")
			if(check_ability(user))
				ring(user, ask.stance)
				add_fingerprint(user)

		if("pick up")
			// The standard hand pickup (the item's "Pick up" interaction), with all its checks.
			if(isliving(user) && user.Adjacent(src))
				pick_up_by_hand(user)

/obj/item/deskbell/proc/ring(mob/user, stance = I_HELP)
	if(stance == I_HURT)
		playsound(src, 'sound/effects/deskbell_rude.ogg', 50, 1)
		to_chat(user,span_notice("You hammer [src] rudely!"))
		if (prob(2))
			break_bell(user)
	else
		playsound(src, 'sound/effects/deskbell.ogg', 50, 1)
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

/// Old attackby.
/obj/item/deskbell/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(!istype(W))
		return INTERACTION_HANDLED_PASS
	if(!broken)
		ring(user, interaction.stance)
	return INTERACTION_HANDLED_PASS

/obj/item/deskbell/wrench_act(mob/user, obj/item/W)
	if(!isturf(loc))
		return TRUE
	om_task_timed(user, 0.5 SECONDS, target = src, receiver = src, on_done = PROC_REF(wrench_act_timed_done), done_args = list(user))
	return TRUE

/obj/item/deskbell/proc/wrench_act_timed_done(mob/user)
	to_chat(user, span_notice("You disassemble the desk bell."))
	replace_with(src, /obj/item/stack/material/steel, 1)

/obj/item/deskbell/proc/break_bell(mob/user)
	to_chat(user,span_notice("The ringing abruptly stops as [src]'s ringer gets jammed inside!"))
	broken = 1
