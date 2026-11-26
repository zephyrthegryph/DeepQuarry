/proc/generate_speech_bubble(bubble_loc, speech_state, set_layer = FLOAT_LAYER)
	var/image/I = image('icons/mob/talk_vr.dmi', bubble_loc, speech_state, set_layer) // talk_vr.dmi instead of talk.dmi for right-side icons
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	/* // Removal Start
	if(istype(bubble_loc, /atom/movable))
		var/atom/movable/AM = bubble_loc
		var/x_scale = AM.get_icon_scale_x()
		if(abs(x_scale) < 2) // reset transform on bubbles, except for the Very Large
			I.pixel_z = (motion_of(AM).icon_height * (x_scale-1))
			I.appearance_flags |= RESET_TRANSFORM
	*/ // Removal Start
	return I

// The speech hotkeys (keybinding_defaults.dm) focus the chat input row in their channel (/client/proc/chat_focus_input); until the chat
// page has loaded they fall back to the plain verb prompt.

/mob/verb/say_wrapper()
	set name = "Say verb"
	set hidden = TRUE

	if(client?.chat_focus_input(SAY_CHANNEL))
		return
	ask_chat_line("Speak to people in sight.\nType your message:", "Say", /mob/verb/say_verb)

/mob/verb/me_wrapper()
	set name = "Me verb"
	set hidden = TRUE

	if(client?.chat_focus_input(ME_CHANNEL))
		return
	ask_chat_line("Emote to people in sight (and your pred/prey).\nType your message:", "Emote", /mob/verb/me_verb, TRUE)

/mob/verb/whisper_wrapper()
	set name = "Whisper verb"
	set hidden = TRUE

	if(client?.chat_focus_input(WHIS_CHANNEL))
		return
	ask_chat_line("Speak to nearby people.\nType your message:", "Whisper", /mob/verb/whisper)

/mob/verb/subtle_wrapper()
	set name = "Subtle verb"
	set hidden = TRUE
	set desc = "Emote to nearby people (and your pred/prey)"

	if(client?.chat_focus_input(SUBTLE_CHANNEL))
		return
	ask_chat_line("Emote to nearby people (and your pred/prey).\nType your message:", "Subtle", /mob/verb/me_verb_subtle, TRUE)
