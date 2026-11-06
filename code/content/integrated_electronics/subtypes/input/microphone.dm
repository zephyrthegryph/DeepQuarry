/obj/item/integrated_circuit/input/microphone
	name = "microphone"
	desc = "Useful for spying on people or for voice activated machines."
	extended_desc = "This will automatically translate most languages it hears to Galactic Common.  \
	The first activation pin is always pulsed when the circuit hears someone talk, while the second one \
	is only triggered if it hears someone speaking a language other than Galactic Common."
	icon_state = "recorder"
	complexity = 8
	inputs = list()
	outputs = list(
	"speaker ref",
	"speaker" = IC_PINTYPE_STRING,
	"message" = IC_PINTYPE_STRING
	)
	activators = list("on message received" = IC_PINTYPE_PULSE_OUT, "on translation" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 15

DECLARE_REGISTRY(/obj/item/integrated_circuit/input/microphone, REGISTRY_LISTENING_OBJECTS)

/obj/item/integrated_circuit/input/microphone/hear_talk(mob/M, list/message_pieces, verb)
	var/msg = multilingual_to_message(message_pieces, requires_machine_understands = TRUE)

	var/translated = FALSE
	if(M && msg)
		for(var/datum/multilingual_say_piece/S in message_pieces)
			// S.speaking && here is not redundant, it's preventing `S.speaking = null` from flagging
			// as a translation, when it is not.
			if(S.speaking && !istype(S.speaking, /datum/language/common))
				translated = TRUE
		set_pin_data(IC_OUTPUT , 1, ic_ref(M))
		set_pin_data(IC_OUTPUT, 2, M.GetVoice())
		set_pin_data(IC_OUTPUT, 3, msg)

	push_data()
	activate_pin(1)
	if(translated)
		activate_pin(2)
