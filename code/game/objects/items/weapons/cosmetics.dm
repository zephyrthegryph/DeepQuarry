/obj/item/lipstick
	gender = PLURAL
	name = "red lipstick"
	desc = "A generic brand of lipstick."
	icon = 'icons/obj/items.dmi'
	icon_state = "lipstick"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	var/colour = "red"
	var/open = 0
	drop_sound = 'sound/items/drop/glass.ogg'
	pickup_sound = 'sound/items/pickup/glass.ogg'

/obj/item/lipstick/purple
	name = "purple lipstick"
	colour = "purple"

/obj/item/lipstick/jade
	name = "jade lipstick"
	colour = "jade"

/obj/item/lipstick/black
	name = "black lipstick"
	colour = "black"

/obj/item/lipstick/random
	name = "lipstick"

/obj/item/lipstick/random/Initialize(mapload)
	. = ..()
	colour = pick("red","purple","jade","black")
	name = "[colour] lipstick"

DECLARE_INTERACTIONS(/obj/item/lipstick, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/lipstick/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You twist \the [src] [open ? "closed" : "open"]."))
	open = !open
	if(open)
		icon_state = "[initial(icon_state)]_[colour]"
	else
		icon_state = initial(icon_state)
	return TRUE

/obj/item/lipstick/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!open)
		return ITEM_INTERACT_FAILURE

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.lip_style)	//if they already have lipstick on
			to_chat(user, span_notice("You need to wipe off the old lipstick first!"))
			return ITEM_INTERACT_FAILURE
		if(H == user)
			user.visible_message(span_notice("[user] does their lips with \the [src]."), \
									span_notice("You take a moment to apply \the [src]. Perfect!"))
			H.lip_style = colour
			H.update_icons_body()
			return ITEM_INTERACT_SUCCESS
		else
			user.visible_message(span_warning("[user] begins to do [H]'s lips with \the [src]."), \
									span_notice("You begin to apply \the [src]."))
			om_task_timed(user, 2 SECONDS, target = H, receiver = src, on_done = PROC_REF(attack_timed_done), done_args = list(user, H))
			return ITEM_INTERACT_SUCCESS
	else
		to_chat(user, span_notice("Where are the lips on that?"))
		return ITEM_INTERACT_FAILURE

/obj/item/lipstick/proc/attack_timed_done(mob/living/user, mob/living/carbon/human/H)
	user.visible_message(span_notice("[user] does [H]'s lips with \the [src]."), \
							span_notice("You apply \the [src]."))
	H.lip_style = colour
	H.update_icons_body()
	return ITEM_INTERACT_SUCCESS

//you can wipe off lipstick with paper! see code/modules/paperwork/paper.dm, paper/attack()

/obj/item/haircomb //sparklysheep's comb
	name = "purple comb"
	desc = "A pristine purple comb made from flexible plastic."
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	icon = 'icons/obj/items.dmi'
	icon_state = "purplecomb"

DECLARE_INTERACTIONS(/obj/item/haircomb, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/haircomb/proc/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	var/text = "person"
	if(ishuman(user))
		var/mob/living/carbon/human/U = user
		switch(U.identifying_gender)
			if(MALE)
				text = "guy"
			if(FEMALE)
				text = "lady"
	else
		switch(user.gender)
			if(MALE)
				text = "guy"
			if(FEMALE)
				text = "lady"
	user.visible_message(span_notice("[user] uses [src] to comb their hair with incredible style and sophistication. What a [text]."))
	return TRUE

/obj/item/makeover
	name = "makeover kit"
	desc = "A tiny case containing a mirror and some contact lenses."
	w_class = ITEMSIZE_TINY
	icon = 'icons/obj/items.dmi'
	icon_state = "trinketbox"
	var/datum/tgui_module/appearance_changer/mirror/coskit/M

/obj/item/makeover/Initialize(mapload)
	. = ..()
	M = new(src, null)

DECLARE_INTERACTIONS(/obj/item/makeover, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/makeover/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(user))
		to_chat(user, span_notice("You flip open \the [src] and begin to adjust your appearance."))
		M.tgui_interact(user)
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if(istype(E))
			E.change_eye_color()
	return TRUE

DECLARE_REF(/obj/item/makeover, "M", OWNED, null)
