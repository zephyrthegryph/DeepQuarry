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
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

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

TRACKED(/obj/item/lipstick, open)

MSG_DEF_SELF(lipstick/closed, "Twist it open first.")

CAPABILITIES(/obj/item/lipstick)
	op("twist", in_hand(), label("Twist lipstick"), then(PROC_REF(twisted)))
	op("apply", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Apply lipstick"),
		needs(req_adjacent(), req_is(nameof(open), TRUE, because = MSG(lipstick/closed)), req_bool(PROC_REF(clean_lips), because = PROC_REF(lip_refusal))),
		then(PROC_REF(application_started), early = TRUE), wait(PROC_REF(application_delay)), then(PROC_REF(lipstick_applied)))

/obj/item/lipstick/proc/twisted(datum/act/op/A)
	to_chat(A.actor, span_notice("You twist \the [src] [open ? "closed" : "open"]."))
	set_open(!open)
	icon_state = open ? "[initial(icon_state)]_[colour]" : initial(icon_state)
	return OP_OK

/obj/item/lipstick/proc/clean_lips(datum/act/op/A)
	if(!ishuman(A.target))
		return FALSE
	var/mob/living/carbon/human/H = A.target
	return !H.lip_style

/obj/item/lipstick/proc/lip_refusal(datum/act/op/A)
	return span_notice(ishuman(A.target) ? "You need to wipe off the old lipstick first!" : "Where are the lips on that?")

/obj/item/lipstick/proc/application_delay(datum/act/op/A)
	return A.target == A.actor ? 0 : 2 SECONDS

/obj/item/lipstick/proc/application_started(datum/act/op/A)
	if(A.target != A.actor)
		act_message(A.actor, src, MSG_SELF(span_notice("You begin to apply %T%.")), \
			MSG_OTHERS(span_warning("%U% begins to do [A.target]'s lips with %T%.")))
	return OP_OK

/obj/item/lipstick/proc/lipstick_applied(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	if(H == A.actor)
		act_message(A.actor, src, MSG_SELF(span_notice("You take a moment to apply %T%. Perfect!")), \
			MSG_OTHERS(span_notice("%U% does their lips with %T%.")))
	else
		act_message(A.actor, src, MSG_SELF(span_notice("You apply %T%.")), \
			MSG_OTHERS(span_notice("%U% does [H]'s lips with %T%.")))
	H.set_lip_style(colour)
	H.update_icons_body()
	return OP_OK

//you can wipe off lipstick with paper! see code/modules/paperwork/paper.dm, paper/attack()

/obj/item/haircomb //sparklysheep's comb
	name = "purple comb"
	desc = "A pristine purple comb made from flexible plastic."
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	icon = 'icons/obj/items.dmi'
	icon_state = "purplecomb"

CAPABILITIES(/obj/item/haircomb)
	op("comb", in_hand(), label("Comb hair"), then(PROC_REF(hair_combed)))

/obj/item/haircomb/proc/hair_combed(datum/act/op/A)
	var/mob/user = A.actor
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
	act_message(user, src, others = span_notice("%U% uses %T% to comb their hair with incredible style and sophistication. What a [text]."))
	return OP_OK

/obj/item/makeover
	name = "makeover kit"
	desc = "A tiny case containing a mirror and some contact lenses."
	w_class = ITEMSIZE_TINY
	icon = 'icons/obj/items.dmi'
	icon_state = "trinketbox"
	var/datum/tgui_module/appearance_changer/mirror/coskit/M


CAPABILITIES(/obj/item/makeover)
	owns_one(nameof(M), starts = /datum/tgui_module/appearance_changer/mirror/coskit)
	op("makeover", in_hand(), label("Adjust appearance"), needs(req_actor_kind(/mob/living/carbon/human)), then(PROC_REF(appearance_adjusted)))

/obj/item/makeover/proc/appearance_adjusted(datum/act/op/A)
	var/mob/user = A.actor
	if(ishuman(user))
		to_chat(user, span_notice("You flip open \the [src] and begin to adjust your appearance."))
		M.tgui_interact(user)
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if(istype(E))
			E.change_eye_color()
	return OP_OK
