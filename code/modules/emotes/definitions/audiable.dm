/datum/decl/emote/audible/wheeze
	emote_sound = SFX_VOICE_WHEEZE

/datum/decl/emote/audible/prbt2
	key = "prbt2"
	emote_message_1p = "You prbt."
	emote_message_3p = "prbts."
	emote_message_1p_target = "You prbt at TARGET."
	emote_message_3p_target = "prbts at TARGET."
	emote_sound = SFX_VOICE_PRBT2

/datum/decl/emote/audible/gasp/get_emote_sound(atom/user)
	..()
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		// Standardize Species Sounds Getters
		var/vol = H.species.gasp_volume
		var/s = get_species_sound(get_gendered_sound(H))["gasp"]
		if(!s && !(get_species_sound(H.species.species_sounds) == "None")) // Failsafe, so we always use the default gasp/etc sounds. None will cancel out anyways.
			if(H.identifying_gender == FEMALE)
				s = get_species_sound("Human Female")["gasp"]
			else // Update this if we ever get herm/etc sounds.
				s = get_species_sound("Human Male")["gasp"]
		return list(
				"sound" = s,
				"vol" = vol,
				"volchannel" = VOLUME_CHANNEL_SPECIES_SOUNDS
			)

/datum/decl/emote/audible/mgeow
	key = "mgeow"
	emote_message_1p = "You mgeow."
	emote_message_3p = "mgeows."
	emote_message_1p_target = "You mgeow at TARGET."
	emote_message_3p_target = "mgeow at TARGET."
	emote_sound = SFX_VOICE_MGEOW

/datum/decl/emote/audible/xenogrowl
	key = "xenogrowl"
	emote_message_1p = "You growl unnervingly."
	emote_message_3p = "growls unnervingly."
	emote_message_1p_target = "You growl unnervingly at TARGET."
	emote_message_3p_target = "growls unnervingly at TARGET."
	emote_sound = SFX_VOICE_EMOTES_XENOGROWL

/datum/decl/emote/audible/xenohiss
	key = "xenohiss"
	emote_message_1p = "You hiss unnervingly."
	emote_message_3p = "hisses unnervingly."
	emote_message_1p_target = "You hiss unnervingly at TARGET."
	emote_message_3p_target = "hisses unnervingly at TARGET."
	emote_sound = SFX_VOICE_EMOTES_XENOHISS

/datum/decl/emote/audible/xenopurr
	key = "xenopurr"
	emote_message_1p = "You purr unnervingly."
	emote_message_3p = "purrs unnervingly."
	emote_message_1p_target = "You purr unnervingly at TARGET."
	emote_message_3p_target = "purrs unnervingly at TARGET."
	emote_sound = SFX_VOICE_EMOTES_XENOPURR

/datum/decl/emote/audible/gwah
	key = "gwah"
	emote_message_1p = "You gwah."
	emote_message_3p = "gwahs."
	emote_message_1p_target = "You gwah at TARGET."
	emote_message_3p_target = "gwahs at TARGET."
	emote_sound = SFX_VOICE_EMOTES_GWAH

/datum/decl/emote/audible/wawa
	key = "wawa"
	emote_message_1p = "You wawa."
	emote_message_3p = "wawas."
	emote_message_1p_target = "You wawa at TARGET."
	emote_message_3p_target = "wawas at TARGET."
	emote_sound = SFX_VOICE_EMOTES_WAWA

/datum/decl/emote/audible/scientist //placeholder, do not use in anything
	key = "hlscientist"
	emote_message_3p = "does science."

/datum/decl/emote/audible/scientist/scream
	key = "hlscream"
	emote_message_1p = "You scream."
	emote_message_3p = "screams."
	emote_message_1p_target = "You scream at TARGET."
	emote_message_3p_target = "screams at TARGET."
	emote_sound = SFX_VOICE_SCREAM_SCIENTIST_SCREAM_MIX

/datum/decl/emote/audible/scientist/pain
	key = "hlpain"
	emote_message_1p = "You shout in pain."
	emote_message_3p = "shouts in pain."
	emote_message_1p_target = "You shout in pain at TARGET."
	emote_message_3p_target = "shouts in pain at TARGET."
	emote_sound = SFX_VOICE_PAIN_SCIENTIST_SCI_PAIN_MIX

/datum/decl/emote/audible/scientist/get_emote_sound(atom/user)
	. = ..()
	.["vol"] *= 0.4 //these boys are pretty loud on their own lol

/datum/decl/emote/audible/yip // sounds sourced from: https://introdile.itch.io/kobold-generator with permission from the creator
	key = "yip"
	emote_message_1p = "You yip."
	emote_message_3p = "yips!"
	emote_message_1p_target = "You yip at TARGET!"
	emote_message_3p_target = "yips at TARGET!"
	emote_sound = SFX_VOICE_EMOTES_YIP_MIX

/datum/decl/emote/audible/squeal // Sound sourced from: https://github.com/Baystation12/Baystation12/blob/bd2f0bd5e38cf2bb0888e3ae879708bed20243b4/sound/voice/LizardSqueal.ogg, licensed Creative Commons 3.0 BY-SA.
	key = "squeal"
	emote_message_1p = "You squeal."
	emote_message_3p = "squeals."
	emote_message_1p_target = "You squeal at TARGET."
	emote_message_3p_target = "squeals at TARGET."
	emote_sound = SFX_VOICE_EMOTES_SQUEALEMOTE

/datum/decl/emote/audible/tailthump // Sound sourced from https://freesound.org/s/389665/ Licensed Creative Commons 0
	key = "tailthump"
	emote_message_1p = "You thump your tail."
	emote_message_3p = "thumps their tail."
	emote_message_1p_target = "You thump your tail at TARGET."
	emote_message_3p_target = "thumps their tail at TARGET."
	emote_sound = SFX_VOICE_EMOTES_TAILTHUMPEMOTE
