/obj/item/hailer
	name = "hailer"
	desc = "Used by obese officers to save their breath for running."
	icon = 'icons/obj/device.dmi'
	icon_state = "voice0"
	item_state = "flashbang"	//looks exactly like a flash (and nothing like a flashbang)
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS

	var/use_message = "Halt! Security!"
	var/insults

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

TRACKED(/obj/item/hailer, use_message)
TRACKED(/obj/item/hailer, insults)

CAPABILITIES(/obj/item/hailer)
	held_verb(/obj/item/hailer/proc/set_hailer_message, SLOT_ANY_CARRIED)
	op("hail", in_hand(), label("Hail"), cooldown(2 SECONDS), then(PROC_REF(hailed)))
	op("set_message", menu(), label("Set Hailer Message"), needs(carried(), req_capable(), req(PROC_REF(unfried), because = "the hailer is fried, the tiny input screen just shows a waving ASCII penis")),
		asks(/datum/prompt/text, keeps = 0, fields = list("timeout" = 0, "question" = "Please enter new message (leave blank to reset).")), then(PROC_REF(message_picked)))
	emag(list(needs(req(PROC_REF(unfried), because = "The hailer is fried. You can't even fit the sequencer into the input slot.")), then(PROC_REF(overloaded))), repeatable = TRUE)

/obj/item/hailer/proc/set_hailer_message()
	set name = "Set Hailer Message"
	set category = VERB_CAT_OBJECT
	set src in usr
	perform_op(usr, src, "set_message", null, ORIGIN_VERB)

/obj/item/hailer/proc/unfried(datum/act/op/A)
	return (isnull(insults)) ? null : "the hailer is fried, the tiny input screen just shows a waving ASCII penis"

/obj/item/hailer/proc/message_picked(datum/act/op/A)
	var/datum/prompt/text/ask = A.answer
	set_use_message(ask.value ? capitalize(ask.value) : "Halt! Security!")
	to_chat(A.actor, "You configure the hailer to shout \"[use_message]\".")
	return OP_OK

/obj/item/hailer/proc/hailed(datum/act/op/A)
	var/mob/user = A.actor
	if(isnull(insults))
		play_sfx(src, SFX_VOICE_HALT)
		user.audible_message(span_warning("[user]'s [name] rasps, \"[use_message]\""), span_warning("\The [user] holds up \the [name]."), runemessage = "\[TTS Voice\] [use_message]")
	else
		if(insults > 0)
			play_sfx(src, SFX_VOICE_BINSULT)
			user.audible_message(span_warning("[user]'s [name] gurgles something indecipherable and deeply offensive."), span_warning("\The [user] holds up \the [name]."), runemessage = "\[TTS Voice\] #&@&^%(*")
			set_insults(insults - 1)
		else
			to_chat(user, span_danger("*BZZZZZZZZT*"))
	return OP_OK

/obj/item/hailer/proc/overloaded(datum/act/op/A)
	to_chat(A.actor, span_danger("You overload \the [src]'s voice synthesizer."))
	set_insults(rand(1, 3))
	return OP_OK
