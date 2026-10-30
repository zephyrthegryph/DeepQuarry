MATERIAL_MIX(/obj/item/assembly/voice, list(MAT_STEEL = 500, MAT_GLASS = 50))
/obj/item/assembly/voice
	name = "voice analyzer"
	desc = "A small electronic device able to record a voice sample, and send a signal when that sample is repeated."
	icon_state = "voice"
	var/listening = 0
	var/recorded	//the activation message
	special_handling = TRUE

/obj/item/assembly/voice/hear_talk(mob/M, list/message_pieces, verb)
	var/msg = multilingual_to_message(message_pieces)
	if(listening)
		recorded = msg
		listening = 0
		var/turf/T = get_turf(src)	//otherwise it won't work in hand
		T.visible_message("[icon2html(src,viewers(src))] beeps, \"Activation message is '[recorded]'.\"")
	else
		if(findtext(msg, recorded))
			pulse(0)

/obj/item/assembly/voice/activate()
	if(secured)
		if(!holder())
			listening = !listening
			var/turf/T = get_turf(src)
			T.visible_message("[icon2html(src,viewers(src))] beeps, \"[listening ? "Now" : "No longer"] recording input.\"")


/// Overrides assembly's interaction_self(): activate instead of opening the UI.
/obj/item/assembly/voice/interaction_self(datum/act/op/A)
	activate()
	return OP_OK

/obj/item/assembly/voice/toggle_secure()
	. = ..()
	listening = 0
