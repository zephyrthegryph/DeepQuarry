// The sound system's API (code/game/sound_service.dm declares the system).
//
//   SSsounds.ready()                          the system, set up on first use (it is lazy)
//   SSsounds.random_available_channel()       a channel number for a one-off sound
//   SSsounds.random_available_channel_text()  the same, as text
//   SSsounds.reserve_sound_channel(datum)     a channel reserved for a datum (songs); free it with free_datum_channels()
//   SSsounds.free_datum_channels(datum)       frees every channel a datum reserved
//   SSsounds.talk_sound_sets()                the talk sound table: voice name -> list of sounds
//   SSsounds.talk_sound(voice)                one voice's sounds

/// Typed, so `SSsounds.ready().var` reads as the system's own var.
/datum/system/sounds/ready()
	RETURN_TYPE(/datum/system/sounds)
	return ..()

/// Reserves a channel for a datum, which frees it with free_datum_channels() (songs do when they stop). Returns an integer for channel.
/datum/system/sounds/proc/reserve_sound_channel(datum/D)
	return claim_sound_channel(D)

/// Frees all the channels a datum is using.
/datum/system/sounds/proc/free_datum_channels(datum/D)
	release_datum_channels(D)

/datum/system/sounds/proc/talk_sound_sets()
	return talk_sound_map

/datum/system/sounds/proc/talk_sound(voice)
	return talk_sound_map[voice]

/// Random available channel, returns text.
/datum/system/sounds/proc/random_available_channel_text()
	if(!length(channel_list))
		return
	if(channel_random_low > channel_reserve_high)
		channel_random_low = 1
	. = "[channel_list[channel_random_low++]]"

/// Random available channel, returns number
/datum/system/sounds/proc/random_available_channel()
	if(!length(channel_list))
		return
	if(channel_random_low > channel_reserve_high)
		channel_random_low = 1
	. = channel_list[channel_random_low++]
