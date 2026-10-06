/obj/structure/sign/double/barsign
	desc = "The current barsign of this shift! The bartender can change it with their ID."
	icon = 'icons/obj/barsigns.dmi'
	plane = ABOVE_PLANE
	icon_state = "Empty"
	appearance_flags = 0
	anchored = TRUE
	req_access = list(ACCESS_BAR)
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

MSG_DEF_SELF(barsign/cult, "The sign doesn't respond.")

CAPABILITIES(/obj/structure/sign/double/barsign)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))
	// an ID with bar access changes the face (the sign's req_access); a cult sign is past changing
	op("change_sign", inputs(item(/obj/item/card/id), item(/obj/item/pda)), label("Use"),
		needs(req_is(nameof(cult), FALSE, because = MSG(barsign/cult)), req_credential_in_hand(list(/obj/item/card/id, /obj/item/pda))),
		asks(/datum/prompt/choice, fields = list("title" = "Bar Sign Choice", "question" = "What would you like to change the barsign to?", "choices" = computed(PROC_REF(sign_choices)), "timeout" = 0)),
		then(PROC_REF(sign_chosen)))

/// Rolled before init (rolls()): the sign starts on any of its valid faces.
/obj/structure/sign/double/barsign/proc/roll_icon_state(datum/roller/R)
	return R.choose(get_valid_states())

/// The faces the sign can be set to.
/obj/structure/sign/double/barsign/proc/sign_choices(datum/act/A)
	return get_valid_states(0)

/// The chosen face goes up.
/obj/structure/sign/double/barsign/proc/sign_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R?.value || cult)
		return OP_OK
	icon_state = R.value
	to_chat(A.actor, span_notice("You change the barsign."))
	return OP_OK
