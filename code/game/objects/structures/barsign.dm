/obj/structure/sign/double/barsign
	desc = "The current barsign of this shift! The bartender can change it with their ID."
	icon = 'icons/obj/barsigns.dmi'
	plane = ABOVE_PLANE
	icon_state = "Empty"
	appearance_flags = 0
	anchored = TRUE
	var/cult = 0

/obj/structure/sign/double/barsign/proc/get_valid_states(initial=1)
	. = icon_states_fast(icon)
	. -= "On"
	. -= "Nar-sie Bistro"
	. -= "Empty"
	if(initial)
		. -= "Off"

/obj/structure/sign/double/barsign/examine(mob/user)
	. = ..()
	switch(icon_state)
		if("Off")
			. += "It appears to be switched off."
		if("Nar-sie Bistro")
			. += "It shows a picture of a large black and red being. Spooky!"
		if("On", "Empty")
			. += "The lights are on, but there's no picture."
		else
			. += "It says '[icon_state]'"

/obj/structure/sign/double/barsign/Initialize(mapload)
	. = ..()
	icon_state = pick(get_valid_states())

/obj/structure/sign/double/barsign/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/barsign_item,
	)
	..()

/obj/structure/sign/double/barsign/proc/sign_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	if(cult)
		return
	icon_state = ask.choice
	to_chat(user, span_notice("You change the barsign."))

/// Old attackby: change the sign with an ID card that has bar access.
/datum/interaction/entry_item/barsign_item
	id = "barsign_item"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/structure/sign/double/barsign/proc/barsign_not_cult, null))
	effect = /obj/structure/sign/double/barsign/proc/interaction_item

/obj/structure/sign/double/barsign/proc/barsign_not_cult(mob/actor, atom/target, obj/item/held)
	return !cult

/obj/structure/sign/double/barsign/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	var/obj/item/card/id/card = I.GetID()
	if(istype(card))
		if(ACCESS_BAR in card.GetAccess())
			om_ask(user, /datum/om/prompt/choice, PROC_REF(sign_chosen), choices = get_valid_states(0), title = "Bar Sign Choice", message = "What would you like to change the barsign to?", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
		else
			to_chat(user, span_warning("Access denied."))
	return TRUE
