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

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/hailer/proc/set_message_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(!isnull(insults))
		to_chat(user, "The hailer is fried. The tiny input screen just shows a waving ASCII penis.")
		return

	om_ask(user, /datum/om/prompt/text, PROC_REF(message_entered), message = "Please enter new message (leave blank to reset).", ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/hailer/proc/message_entered(datum/om/prompt/text/ask)
	var/mob/user = ask.answerer
	var/new_message = ask.text
	if(!new_message || new_message == "")
		use_message = "Halt! Security!"
	else
		use_message = capitalize(new_message)

	to_chat(user, "You configure the hailer to shout \"[use_message]\".")

DECLARE_INTERACTIONS(/obj/item/hailer, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/hailer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if (!COOLDOWN_FINISHED(src, spamcheck))
		return

	if(isnull(insults))
		playsound(src, 'sound/voice/halt.ogg', 100, 1, vary = 0)
		user.audible_message(span_warning("[user]'s [name] rasps, \"[use_message]\""), span_warning("\The [user] holds up \the [name]."), runemessage = "\[TTS Voice\] [use_message]")
	else
		if(insults > 0)
			playsound(src, 'sound/voice/binsult.ogg', 100, 1, vary = 0)
			// Yes, it used to show the transcription of the sound clip. That was a) inaccurate b) immature as shit.
			user.audible_message(span_warning("[user]'s [name] gurgles something indecipherable and deeply offensive."), span_warning("\The [user] holds up \the [name]."), runemessage = "\[TTS Voice\] #&@&^%(*")
			insults--
		else
			to_chat(user, span_danger("*BZZZZZZZZT*"))

	COOLDOWN_START(src, spamcheck, 2 SECONDS)

/obj/item/hailer/emag_act(remaining_charges, mob/user)
	if(isnull(insults))
		to_chat(user, span_danger("You overload \the [src]'s voice synthesizer."))
		insults = rand(1, 3)//to prevent dickflooding
		return 1
	else
		to_chat(user, "The hailer is fried. You can't even fit the sequencer into the input slot.")

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/hailer, \
	INTERACT_VERB("Set Hailer Message", PROC_REF(set_message_effect), REQ_IN_INVENTORY), \
)
