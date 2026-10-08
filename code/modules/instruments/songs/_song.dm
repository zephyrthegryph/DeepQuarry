/**
 * # Song datum
 *
 * These are the actual backend behind instruments.
 * They attach to an atom and provide the editor + playback functionality.
 */
/datum/song
	/// Name of the song
	var/name = "Untitled"

	/// ID for syncing songs together
	var/id = ""

	/// The atom we're attached to/playing from
	var/tmp/atom/parent

	/// Our song lines
	var/list/lines

	/// delay between notes in deciseconds
	var/tempo = 5

	/// How far we can be heard
	var/instrument_range = 15


	/// Repeats left
	var/repeat = 0
	/// Maximum times we can repeat
	var/max_repeats = 10

	/// Our volume
	var/volume = 35
	/// Max volume
	var/max_volume = 75
	/// Min volume - This is so someone doesn't decide it's funny to set it to 0 and play invisible songs.
	var/min_volume = 1

	/// What instruments our built in picker can use. The picker won't show unless this is longer than one.
	var/list/allowed_instrument_ids = list("r3grand") // ALLOW(instance_list): d: replaced per instance at runtime (3 assignments)

	//////////// Cached instrument variables /////////////
	/// Instrument we are currently using
	var/tmp/datum/instrument/using_instrument_static
	/// Are we operating in legacy mode (so if the instrument is a legacy instrument)
	var/legacy = FALSE
	//////////////////////////////////////////////////////

	/////////////////// Playing variables ////////////////
	/**
	  * Build by compile_chords()
	  * Must be rebuilt on instrument switch.
	  * Compilation happens when we start playing and is cleared after we finish playing.
	  * Format: list of chord lists, with chordlists having (key1, key2, key3, tempodiv)
	  */
	var/list/compiled_chords
	/// Current section of a long chord we're on, so we don't need to make a billion chords, one for every unit ticklag.
	var/elapsed_delay
	/// Amount of delay to wait before playing the next chord
	var/delay_by
	/// Current chord we're on.
	var/current_chord
	/// Channel as text = current volume percentage but it's 0 to 100 instead of 0 to 1.
	var/list/channels_playing
	/// List of channels that aren't being used, as text. This is to prevent unnecessary freeing and reallocations from the sound and instrument services.
	var/list/channels_idle
	/// Who or what's playing us
	var/tmp/atom/music_player
	//////////////////////////////////////////////////////

	/// Last world.time we checked for who can hear us
	EXPIRY_DECLARE(last_hearcheck)
	/// The list of mobs that can hear us
	var/list/hearing_mobs
	/// If this is enabled, some things won't be strictly cleared when they usually are (liked compiled_chords on play stop)
	var/debug_mode = FALSE
	/// Max sound channels to occupy
	var/max_sound_channels = CHANNELS_PER_INSTRUMENT
	/// Current channels, so we can save a length() call.
	var/using_sound_channels = 0
	/// Last channel to play. text.
	var/last_channel_played
	/// Should we not decay our last played note?
	var/full_sustain_held_note = TRUE

	/////////////////////// DO NOT TOUCH THESE ///////////////////
	var/octave_min = INSTRUMENT_MIN_OCTAVE
	var/octave_max = INSTRUMENT_MAX_OCTAVE
	var/key_min = INSTRUMENT_MIN_KEY
	var/key_max = INSTRUMENT_MAX_KEY
	var/static/list/note_offset_lookup = list(9, 11, 0, 2, 4, 5, 7)
	var/static/list/accent_lookup = list("b" = -1, "s" = 1, "#" = 1, "n" = 0)
	//////////////////////////////////////////////////////////////

	///////////// !!FUN!! - Only works in synthesized mode! /////////////////
	/// Note numbers to shift.
	var/note_shift = 0
	var/note_shift_min = -100
	var/note_shift_max = 100
	/// The kind of sustain we're using
	var/sustain_mode = SUSTAIN_LINEAR
	/// When a note is considered dead if it is below this in volume
	var/sustain_dropoff_volume = 0
	/// Total duration of linear sustain for 100 volume note to get to SUSTAIN_DROPOFF
	var/sustain_linear_duration = 5
	/// Exponential sustain dropoff rate per decisecond
	var/sustain_exponential_dropoff = 1.4

/// Are we currently playing? song_step() plays the song while set (the every() below).
/datum/song/var/playing = FALSE
TRACKED(/datum/song, playing)

/datum/song/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(song_step), when = nameof(playing))

/datum/song/New(atom/parent, list/instrument_ids, new_range)
	..()
	lifecycle_decls_init(src) // starts the declaration (a non-atom has no materialize)
	join_registries() // REGISTRY_SONGS; the destroy transaction leaves it
	lines = list()
	tempo = sanitize_tempo(tempo, TRUE)
	rel_set(src, nameof(parent), parent)
	if(instrument_ids)
		allowed_instrument_ids = islist(instrument_ids) ? instrument_ids : list(instrument_ids)
	if(length(allowed_instrument_ids))
		set_instrument(allowed_instrument_ids[1])
	volume = clamp(volume, min_volume, max_volume)
	if(new_range)
		instrument_range = new_range

// stops playing and leaves its instrument.

/datum/song/on_destroy(force)
	stop_playing()
	..()

/**
 * Checks and stores which mobs can hear us. Terminates sounds for mobs that leave our range.
 */
/datum/song/proc/do_hearcheck()
	EXPIRY_STAMP(src, last_hearcheck, CLOCK_WORLD)
	var/list/old = hearing_mobs ? hearing_mobs.Copy() : list()
	var/turf/source = get_turf(parent())
	// FIXME
	// for(var/mob/M in get_hearers_in_view(instrument_range, source))
	var/list/in_range = get_mobs_and_objs_in_view_fast(source, instrument_range, remote_ghosts = FALSE)
	var/list/now = list()
	for(var/mob/M in in_range["mobs"])
		now += M
	// hearing_mobs is a relation list: a deleted hearer leaves it by itself; stop_playing() still
	// terminates the sound of every hearer left in it.
	for(var/mob/M as anything in old - now)
		rel_remove(src, nameof(hearing_mobs), M)
		terminate_sound_mob(M)
	for(var/mob/M as anything in now - old)
		rel_add(src, nameof(hearing_mobs), M)

/**
 * Sets our instrument, caching anything necessary for faster accessing. Accepts an ID, typepath, or instantiated instrument datum.
 */
/datum/song/proc/set_instrument(datum/instrument/I)
	terminate_all_sounds()
	var/old_legacy
	if(using_instrument())
		rel_remove(using_instrument(), nameof(/datum/instrument::songs_using), src)
		old_legacy = (using_instrument().instrument_flags & INSTRUMENT_LEGACY)
	using_instrument_static = null
	legacy = null
	if(istext(I) || ispath(I))
		I = SSinstruments.ready().instrument_data[I]
	if(istype(I))
		using_instrument_static = I
		rel_add(I, nameof(I.songs_using), src)
		var/instrument_legacy = (I.instrument_flags & INSTRUMENT_LEGACY)
		if(instrument_legacy)
			legacy = TRUE
		else
			legacy = FALSE
		if(isnull(old_legacy) || (old_legacy != instrument_legacy))
			if(playing)
				compile_chords()

/**
 * Attempts to start playing our song.
 */
/datum/song/proc/start_playing(atom/user)
	if(playing)
		return
	if(!using_instrument()?.ready())
		to_chat(user, span_warning("An error has occured with [src]. Please reset the instrument."))
		return
	compile_chords()
	if(!length(compiled_chords))
		to_chat(user, span_warning("Song is empty."))
		return
	set_playing(TRUE)
	//we can not afford to runtime, since we are going to be doing sound channel reservations and if we runtime it means we have a channel allocation leak.
	//wrap the rest of the stuff to ensure stop_playing() is called.
	do_hearcheck()
	PUBLISH_LEGACY(parent(), /datum/notice/instrument_start, src, user)
	elapsed_delay = 0
	delay_by = 0
	current_chord = 1
	rel_set(src, nameof(music_player), user)
	if(id)
		sync_play()

/**
 * Attempts to find other instruments with the same ID and syncs them to our song.
 */
REGISTRY_MEMBERSHIP(/datum/song, REGISTRY_SONGS)

/datum/song/proc/sync_play()
	for(var/datum/song/other_instrument as anything in REGISTRY_MEMBERS(REGISTRY_SONGS))
		if(other_instrument == src || other_instrument.id != id)
			continue
		if(other_instrument.playing)
			continue
		var/atom/other_player = other_instrument.find_sync_player()
		if(isnull(other_player) || !(other_player in view(get_turf(parent()))))
			continue
		// copies the main song info to target songs
		other_instrument.lines = lines.Copy()
		other_instrument.max_repeats = max_repeats
		other_instrument.tempo = tempo
		other_instrument.start_playing(other_player)

/**
 * Finds a player which would reasonably be able to play this song.
 */
/datum/song/proc/find_sync_player()
	return null

/**
 * Stops playing, terminating all sounds if in synthesized mode. Clears hearing_mobs.
 *
 * Arguments:
 * * finished: boolean, whether the song ended via reaching the end.
 */
/datum/song/proc/stop_playing(finished = FALSE)
	if(!playing)
		return
	set_playing(FALSE)
	if(!debug_mode)
		compiled_chords = null
	PUBLISH_LEGACY(parent(), /datum/notice/instrument_end, finished)
	terminate_all_sounds(TRUE)
	rel_clear(src, nameof(hearing_mobs))
	rel_clear(src, nameof(music_player))

/**
 * Processes our song.
 */
/datum/song/proc/process_song(wait)
	if(!length(compiled_chords))
		stop_playing(TRUE)
		return
	if(should_stop_playing(music_player()) == STOP_PLAYING)
		stop_playing(FALSE)
		return
	var/list/chord = compiled_chords[current_chord]
	elapsed_delay++
	if(elapsed_delay < delay_by)
		return
	play_chord(chord)
	elapsed_delay = 0
	delay_by = tempodiv_to_delay(chord[length(chord)])
	current_chord++
	if(current_chord <= length(compiled_chords))
		return
	if(!repeat)
		stop_playing(TRUE)
		return
	repeat--
	current_chord = 1

/**
 * Converts a tempodiv to ticks to elapse before playing the next chord, taking into account our tempo.
 */
/datum/song/proc/tempodiv_to_delay(tempodiv)
	if(!tempodiv)
		tempodiv = 1 // no division by 0. some song converters tend to use 0 for when it wants to have no div, for whatever reason.
	return max(1, round((tempo/tempodiv) / world.tick_lag, 1))

/**
 * Compiles chords.
 */
/datum/song/proc/compile_chords()
	legacy ? compile_legacy() : compile_synthesized()

/**
 * Plays a chord.
 */
/datum/song/proc/play_chord(list/chord)
	// last value is timing information
	for(var/i in 1 to (length(chord) - 1))
		legacy ? playkey_legacy(chord[i][1], chord[i][2], chord[i][3], music_player()) : playkey_synth(chord[i], music_player())

/**
 * Checks if we should halt playback.
 */
/datum/song/proc/should_stop_playing(atom/player)
	if(QDELETED(player) || !using_instrument() || !playing)
		return STOP_PLAYING
	return NONE

/// Sets and sanitizes the repeats variable.
/datum/song/proc/set_repeats(new_repeats_value)
	if(playing)
		return //So that people cant keep adding to repeat. If the do it intentionally, it could result in the server crashing.
	repeat = round(new_repeats_value)
	if(repeat < 0)
		repeat = 0
	if(repeat > max_repeats)
		repeat = max_repeats

/**
 * Sanitizes tempo to a value that makes sense and fits the current world.tick_lag.
 */
/datum/song/proc/sanitize_tempo(new_tempo, initializing = FALSE)
	new_tempo = abs(new_tempo)
	return clamp(round(new_tempo, world.tick_lag), world.tick_lag, 5 SECONDS)

/**
 * Gets our beats per minute based on our tempo.
 */
/datum/song/proc/get_bpm()
	return 600 / tempo

/**
 * Sets our tempo from a beats-per-minute, sanitizing it to a valid number first.
 */
/datum/song/proc/set_bpm(bpm)
	tempo = sanitize_tempo(600 / bpm)

/datum/song/proc/song_step(dt)
	// it's expected this ticks at every world.tick_lag. if it lags, do not attempt to catch up.
	process_song(world.tick_lag)
	process_decay(world.tick_lag)

/// Linear sustain dropoff, in volume per decisecond: a 100-volume note reaches
/// sustain_dropoff_volume after sustain_linear_duration. Derived from the sustain vars on read.
/datum/song/proc/linear_dropoff_rate()
	return max(0, 100 - sustain_dropoff_volume) / sustain_linear_duration

/**
 * Setter for setting output volume.
 */
/datum/song/proc/set_volume(volume)
	src.volume = clamp(round(volume, 1), max(0, min_volume), min(100, max_volume))

/**
 * Setter for setting how low the volume has to get before a note is considered "dead" and dropped
 */
/datum/song/proc/set_dropoff_volume(volume)
	sustain_dropoff_volume = clamp(round(volume, 0.01), INSTRUMENT_MIN_SUSTAIN_DROPOFF, 100)

/**
 * Setter for setting exponential falloff factor.
 */
/datum/song/proc/set_exponential_drop_rate(drop)
	sustain_exponential_dropoff = clamp(round(drop, 0.00001), INSTRUMENT_EXP_FALLOFF_MIN, INSTRUMENT_EXP_FALLOFF_MAX)

/**
 * Setter for setting linear falloff duration.
 */
/datum/song/proc/set_linear_falloff_duration(duration)
	sustain_linear_duration = clamp(round(duration * 10, world.tick_lag), world.tick_lag, INSTRUMENT_MAX_TOTAL_SUSTAIN)

/datum/song/vv_edit_var(var_name, var_value)
	. = ..()
	if(.)
		switch(var_name)
			if(NAMEOF(src, volume))
				set_volume(var_value)
			if(NAMEOF(src, sustain_dropoff_volume))
				set_dropoff_volume(var_value)
			if(NAMEOF(src, sustain_exponential_dropoff))
				set_exponential_drop_rate(var_value)
			if(NAMEOF(src, sustain_linear_duration))
				set_linear_falloff_duration(var_value)

// subtype for handheld instruments, like violin
/datum/song/handheld

/datum/song/handheld/should_stop_playing(atom/player)
	. = ..()
	if(. == STOP_PLAYING || . == IGNORE_INSTRUMENT_CHECKS)
		return
	var/obj/item/instrument/I = parent()
	return I.can_play(player) ? NONE : STOP_PLAYING

/datum/song/handheld/find_sync_player()
	var/obj/item/instrument/instrument = parent()
	var/mob/living/player = get(parent(), /mob/living)
	if(instrument.can_play(player))
		return player
	return null

// subtype for stationary structures, like pianos
/datum/song/stationary

/datum/song/stationary/should_stop_playing(atom/player)
	. = ..()
	if(. == STOP_PLAYING || . == IGNORE_INSTRUMENT_CHECKS)
		return TRUE
	var/obj/structure/musician/M = parent()
	return M.can_play(player) ? NONE : STOP_PLAYING

/datum/song/stationary/find_sync_player()
	var/obj/structure/musician/piano = parent()
	for(var/mob/living/player in view(parent(), 1))
		if(piano.can_play(player))
			return player

	return null

/// the parent this refers to (a relation view: null once it is deleted).
/datum/song/proc/parent() as /atom
	return parent

/// A shared definition/flyweight (never cleared).
/datum/song/proc/using_instrument() as /datum/instrument
	return using_instrument_static

/// the music_player this refers to (a relation view: null once it is deleted).
/datum/song/proc/music_player() as /atom
	return music_player

CAPABILITIES(/datum/song)
	op("start_new_song", ui_act(), then(PROC_REF(ui_act_start_new_song)))
	op("toggle_sustain_hold_indefinitely", ui_act(), then(PROC_REF(ui_act_toggle_sustain_hold_indefinitely)))
	ref_many(nameof(hearing_mobs))
	interface("InstrumentEditor")
	op("play_music", ui_act("play_music"), then(PROC_REF(ui_act_play_music)))
	op("set_instrument_id", ui_act("set_instrument_id", arg("id", schema_text(4096))), then(PROC_REF(ui_act_set_instrument_id)))
	op("change_instrument", ui_act("change_instrument", arg("new_instrument", schema_text(4096))), then(PROC_REF(ui_act_change_instrument)))
	op("tempo", ui_act("tempo", arg("tempo_change", schema_text(4096))), then(PROC_REF(ui_act_tempo)))
	op("import_song", ui_act("import_song"), asks(/datum/prompt/text/song_import, fields = list("title" = computed(PROC_REF(song_title))), step = "song"),
		asks(/datum/prompt/choice/song_import_continue, step = "too_long", when = PROC_REF(import_too_long)), then(PROC_REF(ui_act_import_song)))
	op("add_new_line", ui_act("add_new_line"), asks(/datum/prompt/text/song_line/add, fields = list("title" = computed(PROC_REF(instrument_title))), step = "line"), then(PROC_REF(ui_act_add_new_line)))
	op("delete_line", ui_act("delete_line", arg("line_deleted", num())), then(PROC_REF(ui_act_delete_line)))
	op("modify_line", ui_act("modify_line", arg("line_editing", num())), asks(/datum/prompt/text/song_line/modify, fields = list("title" = computed(PROC_REF(instrument_title)), "default" = computed(PROC_REF(edited_line))), step = "line", when = PROC_REF(line_exists)),
		then(PROC_REF(ui_act_modify_line)))
	op("set_sustain_mode", ui_act("set_sustain_mode", arg("new_mode")), then(PROC_REF(ui_act_set_sustain_mode)))
	op("set_note_shift", ui_act("set_note_shift", arg("amount", num())), then(PROC_REF(ui_act_set_note_shift)))
	op("set_volume", ui_act("set_volume", arg("amount", num())), then(PROC_REF(ui_act_set_volume)))
	op("set_dropoff_volume", ui_act("set_dropoff_volume", arg("amount", num())), then(PROC_REF(ui_act_set_dropoff_volume)))
	op("set_repeat_amount", ui_act("set_repeat_amount", arg("amount", num())), then(PROC_REF(ui_act_set_repeat_amount)))
	op("edit_sustain_mode", ui_act("edit_sustain_mode", arg("amount", num())), then(PROC_REF(ui_act_edit_sustain_mode)))
