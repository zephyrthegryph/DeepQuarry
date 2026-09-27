/obj/item/text_to_speech
	name = "TTS device"
	desc = "A device that speaks an inputted message. Given to crew which can not speak properly or at all."
	icon = 'icons/obj/integrated_electronics/electronic_setups.dmi'
	icon_state = "setup_small"
	w_class = ITEMSIZE_SMALL
	var/named

/obj/item/text_to_speech/get_interactions()
	var/static/list/L = list(
		INTERACT_USE(null, PROC_REF(interaction_self)),
		INTERACT_ALT(null, PROC_REF(interaction_alt)),
	)
	return L

/obj/item/text_to_speech/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.incapacitated(INCAPACITATION_DISABLED))
		to_chat(user, "You cannot activate the device in your state.")
		return

	if(!named)
		to_chat(user, "You input your name into the device.")
		name = "[initial(name)] ([user.real_name])"
		desc = "[initial(desc)] This one is assigned to [user.real_name]."
		named = 1

	user.client?.start_thinking()
	user.client?.start_typing()
	var/message = tgui_input_text(user,"Choose a message to relay to those around you.", "", "", MAX_MESSAGE_LEN)
	user.client?.stop_thinking()

	if(message)
		audible_message("[icon2html(src, user.client)] \The [src.name] states, \"[message]\"", runemessage = "synthesized speech")
		if(ismob(loc))
			loc.runechat_message("\[TTS Voice\] [message]")

/// QOL change: alt-click does the same thing as self-use.
/obj/item/text_to_speech/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	interaction_self(user, held, interaction)
	return TRUE
