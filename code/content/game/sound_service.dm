#define DATUMLESS "NO_DATUM"

// The sound system (was SSsounds): sound channel reservations and the talk sound table. It has no periodic work, so it
// is a lazy system (outside the boot DAG), set up on first use through SSsounds.ready(). The API is in sound_api.dm.
SYSTEM_DEF(sounds)
	name = "Sounds"
	var/static/using_channels_max = CHANNEL_HIGHEST_AVAILABLE //BYOND max channels
	/// Amount of channels to reserve for random usage rather than reservations being allowed to reserve all channels. Also a nice safeguard for when someone screws up.
	var/static/random_channels_min = 50

	// Hey uh these two needs to be initialized fast because the whole "things get deleted before init" thing.
	/// Assoc list, `"[channel]" =` the reserving datum's ref text, or DATUMLESS for an unsafe-reserved channel.
	/// Keyed by ref text, not the datum: a reservation holds no reference to its datum.
	var/list/using_channels
	/// Assoc list reserving datum's ref text (or DATUMLESS) = list(channel1, channel2, ...).
	var/list/using_channels_by_datum
	// Special datastructure for fast channel management
	/// List of all channels as numbers
	var/list/channel_list
	/// Associative list of all reserved channels associated to their position. `"[channel_number]" =` index as number
	var/list/reserved_channels
	/// lower iteration position - Incremented and looped to get "random" sound channels for normal sounds. The channel at this index is returned when asking for a random channel.
	var/channel_random_low
	/// higher reserve position - decremented and incremented to reserve sound channels, anything above this is reserved. The channel at this index is the highest unreserved channel.
	var/channel_reserve_high
	/// Assoc list of character speaking sounds, contains lists of sounds per key for use with pick()
	var/talk_sound_map = list()

/datum/system/sounds/boots_in_dag()
	return FALSE

/datum/system/sounds/initialize()
	initialized = TRUE
	setup_available_channels()
	create_talk_sound_map()
	log_world("Sound service initialized: [length(channel_list)] channels, [length(talk_sound_map)] talk sound sets.")

/datum/system/sounds/stat_entry(msg)
	return "[msg]Reserved: [length(reserved_channels)] | Left: [available_channels_left()]"

/datum/system/sounds/proc/setup_available_channels()
	channel_list = list()
	reserved_channels = list()
	using_channels = list()
	using_channels_by_datum = list()
	for(var/i in 1 to using_channels_max)
		channel_list += i
	channel_random_low = 1
	channel_reserve_high = length(channel_list)

/// Removes a channel from using list.
/datum/system/sounds/proc/free_sound_channel(channel)
	var/text_channel = num2text(channel)
	var/using = using_channels[text_channel]
	using_channels -= text_channel
	if(using) // a datum or datumless reservation
		using_channels_by_datum[using] -= channel
		if(!length(using_channels_by_datum[using]))
			using_channels_by_datum -= using
	free_channel(channel)

/// Frees all the channels a datum is using.
/datum/system/sounds/proc/release_datum_channels(datum/D)
	var/key = (D == DATUMLESS) ? DATUMLESS : ref(D)
	var/list/L = using_channels_by_datum[key]
	if(!L)
		return
	for(var/channel in L)
		using_channels -= num2text(channel)
		free_channel(channel)
	using_channels_by_datum -= key

/// Frees all datumless channels
/datum/system/sounds/proc/free_datumless_channels()
	release_datum_channels(DATUMLESS)

/// NO AUTOMATIC CLEANUP - If you use this, you better manually free it later! Returns an integer for channel.
/datum/system/sounds/proc/reserve_sound_channel_datumless()
	. = reserve_channel()
	if(!.) //oh no..
		return FALSE
	var/text_channel = num2text(.)
	using_channels[text_channel] = DATUMLESS
	LAZYINITLIST(using_channels_by_datum[DATUMLESS])
	using_channels_by_datum[DATUMLESS] += .

/// Reserves a channel for a datum, which frees it with free_datum_channels() (songs do when they stop). Returns an integer for channel.
/datum/system/sounds/proc/claim_sound_channel(datum/D)
	if(!D) //i don't like typechecks but someone will fuck it up
		CRASH("Attempted to reserve sound channel without datum using the managed proc.")
	.= reserve_channel()
	if(!.)
		return FALSE
	var/text_channel = num2text(.)
	var/key = ref(D)
	using_channels[text_channel] = key
	LAZYINITLIST(using_channels_by_datum[key])
	using_channels_by_datum[key] += .

/**
 * Reserves a channel and updates the datastructure. Private proc.
 */
/datum/system/sounds/proc/reserve_channel()
	PRIVATE_PROC(TRUE)
	if(channel_reserve_high <= random_channels_min) // out of channels
		return
	var/channel = channel_list[channel_reserve_high]
	reserved_channels[num2text(channel)] = channel_reserve_high--
	return channel

/**
 * Frees a channel and updates the datastructure. Private proc.
 */
/datum/system/sounds/proc/free_channel(number)
	PRIVATE_PROC(TRUE)
	var/text_channel = num2text(number)
	var/index = reserved_channels[text_channel]
	if(!index)
		CRASH("Attempted to (internally) free a channel that wasn't reserved.")
	reserved_channels -= text_channel
	// push reserve index up, which makes it now on a channel that is reserved
	channel_reserve_high++
	// swap the reserved channel wtih the unreserved channel so the reserve index is now on an unoccupied channel and the freed channel is next to be used.
	channel_list.Swap(channel_reserve_high, index)
	// now, an existing reserved channel will likely (exception: unreserving last reserved channel) be at index
	// get it, and update position.
	var/text_reserved = num2text(channel_list[index])
	if(!reserved_channels[text_reserved]) //if it isn't already reserved make sure we don't accidently mistakenly put it on reserved list!
		return
	reserved_channels[text_reserved] = index

/// How many channels we have left.
/datum/system/sounds/proc/available_channels_left()
	return length(channel_list) - random_channels_min

/// Init talking sound lists
/datum/system/sounds/proc/create_talk_sound_map()
	talk_sound_map["beep-boop"] = DEFAULT_TALK_SOUNDS // first is DEFAULT
	talk_sound_map["goon speak 1"] =list('sound/talksounds/goon/speak_1.ogg', 'sound/talksounds/goon/speak_1_ask.ogg', 'sound/talksounds/goon/speak_1_exclaim.ogg')
	talk_sound_map["goon speak 2"] = list('sound/talksounds/goon/speak_2.ogg', 'sound/talksounds/goon/speak_2_ask.ogg', 'sound/talksounds/goon/speak_2_exclaim.ogg')
	talk_sound_map["goon speak 3"] = list('sound/talksounds/goon/speak_3.ogg', 'sound/talksounds/goon/speak_3_ask.ogg', 'sound/talksounds/goon/speak_3_exclaim.ogg')
	talk_sound_map["goon speak 4"] = list('sound/talksounds/goon/speak_4.ogg', 'sound/talksounds/goon/speak_4_ask.ogg', 'sound/talksounds/goon/speak_4_exclaim.ogg')
	talk_sound_map["goon speak blub"] = list('sound/talksounds/goon/blub.ogg', 'sound/talksounds/goon/blub_ask.ogg', 'sound/talksounds/goon/blub_exclaim.ogg')
	talk_sound_map["goon speak bottalk"] = list('sound/talksounds/goon/bottalk_1.ogg', 'sound/talksounds/goon/bottalk_2.ogg', 'sound/talksounds/goon/bottalk_3.ogg', 'sound/talksounds/goon/bottalk_4.wav')
	talk_sound_map["goon speak buwoo"] = list('sound/talksounds/goon/buwoo.ogg', 'sound/talksounds/goon/buwoo_ask.ogg', 'sound/talksounds/goon/buwoo_exclaim.ogg')
	talk_sound_map["goon speak cow"] = list('sound/talksounds/goon/cow.ogg', 'sound/talksounds/goon/cow_ask.ogg', 'sound/talksounds/goon/cow_exclaim.ogg')
	talk_sound_map["goon speak lizard"] = list('sound/talksounds/goon/lizard.ogg', 'sound/talksounds/goon/lizard_ask.ogg', 'sound/talksounds/goon/lizard_exclaim.ogg')
	talk_sound_map["goon speak pug"] = list('sound/talksounds/goon/pug.ogg', 'sound/talksounds/goon/pug_ask.ogg', 'sound/talksounds/goon/pug_exclaim.ogg')
	talk_sound_map["goon speak pugg"] = list('sound/talksounds/goon/pugg.ogg', 'sound/talksounds/goon/pugg_ask.ogg', 'sound/talksounds/goon/pugg_exclaim.ogg')
	talk_sound_map["goon speak roach"] = list('sound/talksounds/goon/roach.ogg', 'sound/talksounds/goon/roach_ask.ogg', 'sound/talksounds/goon/roach_exclaim.ogg')
	talk_sound_map["goon speak skelly"] = list('sound/talksounds/goon/skelly.ogg', 'sound/talksounds/goon/skelly_ask.ogg', 'sound/talksounds/goon/skelly_exclaim.ogg')
	talk_sound_map["xeno speak"] = list('sound/talksounds/xeno/xenotalk.ogg', 'sound/talksounds/xeno/xenotalk2.ogg', 'sound/talksounds/xeno/xenotalk3.ogg')

#undef DATUMLESS
