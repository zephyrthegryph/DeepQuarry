/obj/item/text_to_speech
	name = "TTS device"
	desc = "A device that speaks an inputted message. Given to crew which can not speak properly or at all."
	icon = 'icons/obj/integrated_electronics/electronic_setups.dmi'
	icon_state = "setup_small"
	w_class = ITEMSIZE_SMALL
	var/named

TRACKED(/obj/item/text_to_speech, named)

CAPABILITIES(/obj/item/text_to_speech)
	op("speak", inputs(in_hand(), hand()), answers(INTENT_USE, INTENT_TOGGLE, INTENT_OPEN, INTENT_EJECT), label("Speak a message"),
		needs(carried(), req_capable()), then(PROC_REF(speech_started), early = TRUE),
		asks(/datum/prompt/text/tts_message, keeps = 0, fields = list("timeout" = 0, "question" = "Choose a message to relay to those around you.", "default" = "")), then(PROC_REF(message_spoken)))

/obj/item/text_to_speech/proc/speech_started(datum/act/op/A)
	var/mob/user = A.actor
	if(!named)
		to_chat(user, "You input your name into the device.")
		name = "[initial(name)] ([user.real_name])"
		desc = "[initial(desc)] This one is assigned to [user.real_name]."
		set_named(TRUE)
	user.client?.start_thinking()
	user.client?.start_typing()
	return OP_OK

/datum/prompt/text/tts_message/refusal(given)
	if(!istext(given))
		return "That is not text."
	return ..()

/// request_end dismisses native prompts on every outcome, including cancellation and timeout.
/datum/prompt/text/tts_message/dismiss()
	var/mob/user = answerer
	user?.client?.stop_thinking()
	return ..()

/obj/item/text_to_speech/proc/message_spoken(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/text/ask = A.answer
	var/message = ask.value
	if(message)
		audible_message("[icon2html(src, user.client)] \The [src.name] states, \"[message]\"", runemessage = "synthesized speech")
		if(ismob(loc))
			loc.runechat_message("\[TTS Voice\] [message]")
	return OP_OK
