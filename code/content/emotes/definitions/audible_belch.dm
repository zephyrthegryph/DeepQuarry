/datum/decl/emote/audible/belch
	key = "belch"
	emote_message_3p = "belches."
	message_type = AUDIBLE_MESSAGE

/datum/decl/emote/audible/belch/get_emote_sound(atom/user)
	return list(
			"sound" = sound(get_sfx(SFX_BELCHES)),
			"vol" = emote_volume / 2
		)
