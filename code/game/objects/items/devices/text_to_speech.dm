/obj/item/text_to_speech
	name = "TTS device"
	desc = "A device that speaks an inputted message. Given to crew which can not speak properly or at all."
	icon = 'icons/obj/integrated_electronics/electronic_setups.dmi'
	icon_state = "setup_small"
	w_class = ITEMSIZE_SMALL
	var/named

DECLARE_INTERACTIONS(/obj/item/text_to_speech, \
	INTERACT_USE(null, PROC_REF(interaction_self), REQ_TARGET_STATE(/obj/item/text_to_speech/proc/can_activate)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
)

/// Requirement: the user has to be able to work the device.
/obj/item/text_to_speech/proc/can_activate(mob/user, atom/target, obj/item/held)
	if(user.incapacitated(INCAPACITATION_DISABLED))
		return "you cannot activate the device in your state"
	return TRUE

/obj/item/text_to_speech/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!named)
		to_chat(user, "You input your name into the device.")
		name = "[initial(name)] ([user.real_name])"
		desc = "[initial(desc)] This one is assigned to [user.real_name]."
		named = 1

	user.client?.start_thinking()
	user.client?.start_typing()
	om_ask(user, /datum/om/prompt/text/tts_message, PROC_REF(message_entered))

/// The message to speak. Re-checked on the answer: the device is still carried. A cancel stops the typing indicator.
/datum/om/prompt/text/tts_message
	message = "Choose a message to relay to those around you."
	default = ""
	ask_flags = ASK_CARRIED | ASK_CAPABLE

/datum/om/prompt/text/tts_message/cancelled()
	answerer?.client?.stop_thinking()
	return ..()

/obj/item/text_to_speech/proc/message_entered(datum/om/prompt/text/tts_message/ask)
	var/mob/user = ask.answerer
	var/message = ask.text
	user.client?.stop_thinking()

	if(message)
		audible_message("[icon2html(src, user.client)] \The [src.name] states, \"[message]\"", runemessage = "synthesized speech")
		if(ismob(loc))
			loc.runechat_message("\[TTS Voice\] [message]")

/// QOL change: alt-click does the same thing as self-use.
/obj/item/text_to_speech/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	interaction_self(user, held, interaction)
	return TRUE
