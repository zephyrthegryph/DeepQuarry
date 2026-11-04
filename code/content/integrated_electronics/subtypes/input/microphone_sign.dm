/obj/item/integrated_circuit/input/microphone/sign
	name = "sign-language translator"
	desc = "Useful for spying on people or for sign activated machines."
	extended_desc = "This will automatically translate galactic standard sign language it sees to Galactic Common.  \
	The first activation pin is always pulsed when the circuit sees someone speak sign, while the second one \
	is only triggered if it sees someone speaking a language other than sign language, which it will attempt to \
	lip-read."
	icon_state = "video_camera"
	complexity = 5
	inputs = list()
	outputs = list(
	"speaker ref",
	"speaker" = IC_PINTYPE_STRING,
	"message" = IC_PINTYPE_STRING
	)
	activators = list("on message received" = IC_PINTYPE_PULSE_OUT, "on translation" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 30

	var/static/list/readable_langs = list(
		LANGUAGE_GALCOM,
		LANGUAGE_SOL_COMMON,
		LANGUAGE_TRADEBAND,
		LANGUAGE_GUTTER,
		LANGUAGE_TERMINUS,
		LANGUAGE_SIGN
		)

/obj/item/integrated_circuit/input/microphone/sign/hear_talk(mob/M, list/message_pieces, verb)
	var/msg = multilingual_to_message(message_pieces)

	var/translated = TRUE
	if(M && msg)
		for(var/datum/multilingual_say_piece/S in message_pieces)
			if(!((S.speaking.flags & NONVERBAL) || (S.speaking.flags & SIGNLANG))||S.speaking.name == LANGUAGE_ECHOSONG) //Ignore verbal languages
				return
		set_pin_data(IC_OUTPUT , 1, ic_ref(M))
		set_pin_data(IC_OUTPUT, 2, M.GetVoice())
		set_pin_data(IC_OUTPUT, 3, msg)

	push_data()
	if(!translated)
		activate_pin(1)
	else
		activate_pin(2)

/obj/item/integrated_circuit/input/microphone/sign/hear_signlang(text, verb, datum/language/speaking, mob/M as mob)
	var/translated = TRUE
	if(M && text)
		if(speaking)
			if(!((speaking.flags & NONVERBAL) || (speaking.flags & SIGNLANG))||speaking.name == LANGUAGE_ECHOSONG)
				return
		set_pin_data(IC_OUTPUT, 1, M.GetVoice())
		set_pin_data(IC_OUTPUT, 2, text)

	push_data()
	if(!translated)
		activate_pin(1)
	else
		activate_pin(2)
