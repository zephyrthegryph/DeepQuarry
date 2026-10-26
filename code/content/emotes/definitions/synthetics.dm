/datum/decl/emote/audible/synth
	key = "ping"
	emote_message_3p = "pings."
	emote_sound = SFX_MACHINES_PING

/datum/decl/emote/audible/synth/mob_can_use(mob/living/user)
	if(istype(user) && HAS_SYNTHETIC_BIOLOGY(user))
		return ..()
	return FALSE

/datum/decl/emote/audible/synth/beep
	key = "beep"
	emote_message_3p = "beeps."
	emote_sound = SFX_MACHINES_TWOBEEP
	sound_vary = FALSE

/datum/decl/emote/audible/synth/bing
	key = "bing"
	emote_message_3p = "bings."
	emote_sound = SFX_MACHINES_PING

/datum/decl/emote/audible/synth/buzz
	key = "buzz"
	emote_message_3p = "buzzes."
	emote_sound = SFX_MACHINES_BUZZ_SIGH

/datum/decl/emote/audible/synth/confirm
	key = "confirm"
	emote_message_3p = "emits an affirmative blip."
	emote_sound = SFX_MACHINES_SYNTH_YES

/datum/decl/emote/audible/synth/deny
	key = "deny"
	emote_message_3p = "emits a negative blip."
	emote_sound = SFX_MACHINES_SYNTH_NO

/datum/decl/emote/audible/synth/scary
	key = "scary"
	emote_message_3p = "emits a disconcerting tone."
	emote_sound = SFX_MACHINES_SYNTH_ALERT

/datum/decl/emote/audible/synth/security
	key = "law"
	emote_message_3p = "shows USER_THEIR legal authorization barcode."
	emote_message_3p_target = "shows TARGET USER_THEIR legal authorization barcode."
	emote_sound = SFX_VOICE_BIAMTHELAW

/datum/decl/emote/audible/synth/security/mob_can_use(mob/living/silicon/robot/user)
	return ..() && istype(user) && user.module?.security_emotes

/datum/decl/emote/audible/synth/security/halt
	key = "halt"
	emote_message_3p = "USER's speakers skreech, \"Halt! Security!\"."
	emote_sound = SFX_VOICE_HALT

/datum/decl/emote/audible/synth/dwoop
	key = "dwoop"
	emote_message_1p_target = "You chirp happily at TARGET!"
	emote_message_1p = "You chirp happily."
	emote_message_3p_target = "chirps happily at TARGET!"
	emote_message_3p = "chirps happily."
	emote_sound = SFX_MACHINES_DWOOP

/datum/decl/emote/audible/synth/boop
	key = "roboboop"
	emote_message_1p_target = "You boop at TARGET!"
	emote_message_1p = "You boop."
	emote_message_3p_target = "boops at TARGET!"
	emote_message_3p = "boops."
	emote_sound = SFX_VOICE_ROBOBOOP
	sound_vary = TRUE

/datum/decl/emote/audible/synth/robochirp
	key = "robochirp"
	emote_message_1p_target = "You chirp at TARGET!"
	emote_message_1p = "You chirp."
	emote_message_3p_target = "chirps at TARGET!"
	emote_message_3p = "chirps."
	emote_sound = SFX_VOICE_ROBOCHIRP
	sound_vary = TRUE

/datum/decl/emote/audible/synth/ding
	key = "ding"
	emote_message_1p_target = "You ding at TARGET!"
	emote_message_1p = "You ding."
	emote_message_3p_target = "dings at TARGET!"
	emote_message_3p = "dings."
	emote_sound = SFX_MACHINES_DING
	sound_vary = TRUE

/datum/decl/emote/audible/synth/microwave
	key = "microwave"
	emote_message_1p_target = "You make microwave noises at TARGET!"
	emote_message_1p = "You make microwave noises."
	emote_message_3p_target = "makes microwave noises at TARGET!"
	emote_message_3p = "makes microwave noises."
	emote_sound = SFX_MACHINES_KITCHEN_MICROWAVE_MICROWAVE_MID2
	sound_vary = TRUE
