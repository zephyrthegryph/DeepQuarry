/obj/item/hailer
	name = "hailer"
	desc = "Used by obese officers to save their breath for running."
	icon = 'icons/obj/device.dmi'
	icon_state = "voice0"
	item_state = "flashbang"	//looks exactly like a flash (and nothing like a flashbang)
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS

	var/use_message = "Halt! Security!"
	COOLDOWN_DECLARE(spamcheck)
	var/insults

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

TRACKED(/obj/item/hailer, insults)

CAPABILITIES(/obj/item/hailer)
	op("use", in_hand(), then(PROC_REF(used)))
	op("set_message_effect", menu(), label("Set Hailer Message"), needs(carried(), req(PROC_REF(not_fried), because = MSG(hailer/fried_screen))), then(PROC_REF(set_message_effect)))
	emag(then(PROC_REF(on_emag)), say = MSG(hailer/overloaded), repeatable = TRUE)
	extend("emag.use", needs(req(PROC_REF(not_fried), because = MSG(hailer/fried))))
	extend("emag.subvert", needs(req(PROC_REF(not_fried), because = MSG(hailer/fried))))

MSG_DEF_SELF(hailer/fried_screen, "the hailer is fried, the tiny input screen just shows a waving ASCII penis")
MSG_DEF_SELF(hailer/fried, "The hailer is fried. You can't even fit the sequencer into the input slot.")
MSG_DEF_SELF(hailer/overloaded, "You overload the hailer's voice synthesizer.")

/// A hailer whose synthesizer has not been overloaded.
/obj/item/hailer/proc/not_fried(datum/act/A)
	return isnull(insults)

/// The Set Hailer Message verb: ask for the new text.
/obj/item/hailer/proc/set_message_effect(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(message_entered), answerer = A.actor, question = "Please enter new message (leave blank to reset).", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/item/hailer/proc/message_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/new_message = A.answer.answer_value
	if(!new_message || new_message == "")
		use_message = "Halt! Security!"
	else
		use_message = capitalize(new_message)

	to_chat(user, "You configure the hailer to shout \"[use_message]\".")

/// The in-hand use: shout the message (or an insult, when overloaded).
/obj/item/hailer/proc/used(datum/act/op/A)
	var/mob/user = A.actor
	if (!COOLDOWN_FINISHED(src, spamcheck))
		return OP_OK

	if(isnull(insults))
		play_sfx(src, SFX_VOICE_HALT)
		user.audible_message(span_warning("[user]'s [name] rasps, \"[use_message]\""), span_warning("\The [user] holds up \the [name]."), runemessage = "\[TTS Voice\] [use_message]")
	else
		if(insults > 0)
			play_sfx(src, SFX_VOICE_BINSULT)
			// Yes, it used to show the transcription of the sound clip. That was a) inaccurate b) immature as shit.
			user.audible_message(span_warning("[user]'s [name] gurgles something indecipherable and deeply offensive."), span_warning("\The [user] holds up \the [name]."), runemessage = "\[TTS Voice\] #&@&^%(*")
			set_insults(insults - 1)
		else
			to_chat(user, span_danger("*BZZZZZZZZT*"))

	COOLDOWN_START(src, spamcheck, 2 SECONDS)
	return OP_OK

/// A sequencer overloads the voice synthesizer: it will only insult, a few times.
/obj/item/hailer/proc/on_emag(datum/act/op/A)
	set_insults(rand(1, 3)) //to prevent dickflooding
	return OP_OK
