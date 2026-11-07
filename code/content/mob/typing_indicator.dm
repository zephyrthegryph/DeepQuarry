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
	say_verb_old()

/mob/verb/me_wrapper()
	set name = "Me verb"
	set hidden = TRUE

	if(client?.chat_focus_input(ME_CHANNEL))
		return
	me_verb_old()

/mob/verb/whisper_wrapper()
	set name = "Whisper verb"
	set hidden = TRUE

	if(client?.chat_focus_input(WHIS_CHANNEL))
		return
	whisper_old()

/mob/verb/subtle_wrapper()
	set name = "Subtle verb"
	set hidden = TRUE
	set desc = "Emote to nearby people (and your pred/prey)"

	if(client?.chat_focus_input(SUBTLE_CHANNEL))
		return
	me_verb_subtle_old()
