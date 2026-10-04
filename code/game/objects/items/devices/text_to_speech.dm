/obj/item/text_to_speech
	name = "TTS device"
	desc = "A device that speaks an inputted message. Given to crew which can not speak properly or at all."
	icon = 'icons/obj/integrated_electronics/electronic_setups.dmi'
	icon_state = "setup_small"
	w_class = ITEMSIZE_SMALL
	var/named

CAPABILITIES(/obj/item/text_to_speech)
	op("use", in_hand(), needs(req(PROC_REF(can_activate), because = MSG(tts/disabled))), then(PROC_REF(used)))
	op("alt", hand(), gesture(GESTURE_ALT), then(PROC_REF(used)))

MSG_DEF_SELF(tts/disabled, "you cannot activate the device in your state")

/// Requirement: the user has to be able to work the device.
/obj/item/text_to_speech/proc/can_activate(datum/act/op/A)
	return !A.actor.incapacitated(INCAPACITATION_DISABLED)

/// The use and the alt-click do the same: name the device for its first user, then ask what it should say.
/obj/item/text_to_speech/proc/used(datum/act/op/A)
	var/mob/user = A.actor
	if(!named)
		to_chat(user, "You input your name into the device.")
		name = "[initial(name)] ([user.real_name])"
		desc = "[initial(desc)] This one is assigned to [user.real_name]."
		named = 1

	user.client?.start_thinking()
	user.client?.start_typing()
	open_request(src, /datum/prompt/text, PROC_REF(message_entered), answerer = user, question = "Choose a message to relay to those around you.", default = "", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return OP_OK

/// The message to speak. Any end of the question, an answer or a cancel, stops the typing indicator; the re-check that the device is still carried ran before.
/obj/item/text_to_speech/proc/message_entered(datum/act/request/A)
	var/mob/user = A.request.answerer
	user?.client?.stop_thinking()
	if(!A.answer)
		return
	var/message = A.answer.answer_value

	if(message)
		audible_message("[icon2html(src, user.client)] \The [src.name] states, \"[message]\"", runemessage = "synthesized speech")
		if(ismob(loc))
			loc.runechat_message("\[TTS Voice\] [message]")
