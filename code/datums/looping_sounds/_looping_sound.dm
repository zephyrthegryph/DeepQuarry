/*
	output_atoms	(list of atoms)			The destination(s) for the sounds

	mid_sounds		(list or soundfile)		Since this can be either a list or a single soundfile you can have random sounds. May contain further lists but must contain a soundfile at the end.
	mid_length		(num)					The length to wait between playing mid_sounds

	start_sound		(soundfile)				Played before starting the mid_sounds loop
	start_length	(num)					How long to wait before starting the main loop after playing start_sound

	end_sound		(soundfile)				The sound played after the main loop has concluded

	chance			(num)					Chance per loop to play a mid_sound
	volume			(num)					Sound output volume
	muted			(bool)					Private. Used to stop the sound loop.
	max_loops		(num)					The max amount of loops to run for.
	direct			(bool)					If true plays directly to provided atoms instead of from them
	opacity_check	(bool)					If true, things behind walls/opaque things won't hear the sounds.
	pref_check		(type)					If set to a /datum/client_preference type, will check if the hearer has that preference active before playing it to them.
	volume_chan		(type)					If set to a specific volume channel via the incoming argument, we tell the playsound proc to modulate volume based on that channel
	exclusive		(bool)					If true, only one of this sound is allowed to play. Relies on if started is true or not. If true, it will not start another loop until it is false.
*/
/// How often a dormant loop rechecks for listeners without a chunk wake.
#define LOOPING_SOUND_DORMANT_RECHECK (10 SECONDS)

/datum/looping_sound
	var/list/atom/output_atoms
	var/mid_sounds
	var/mid_length
	var/start_sound
	var/start_length
	var/end_sound
	var/chance
	var/volume = 100
	var/max_loops
	var/direct
	var/vary
	var/extra_range
	var/opacity_check
	var/pref_check
	var/exclusive
	var/falloff
	var/volume_chan

	var/timerid
	var/started
	/// Chunk keys this loop is parked on while nobody can hear it; null while it is looping (Q5).
	var/list/dormant_chunk_keys
	/// The starttime the loop had when it went dormant, so max_loops still counts from the real start.
	var/dormant_starttime

/datum/looping_sound/New(list/_output_atoms=list(), start_immediately=FALSE, disable_direct=FALSE)
	if(!mid_sounds)
		WARNING("A looping sound datum was created without sounds to play.")
		return

	output_atoms = _output_atoms
	if(disable_direct)
		direct = FALSE

	if(start_immediately)
		start()

/datum/looping_sound/Destroy()
	stop()
	output_atoms = null
	return ..()

/datum/looping_sound/proc/start(atom/add_thing, skip_start_sound = FALSE)
	if(QDELETED(src))
		return
	if(add_thing)
		output_atoms |= add_thing
	if(timerid)
		return
	if(skip_start_sound && (!exclusive && !started)) // Skip start sounds optionally, check if we're exclusive AND started already
		sound_loop()
		started = TRUE
		return
	if(exclusive && started) // Prevents a sound from starting multiple times
		return // Don't start this loop.
	on_start()
	started = TRUE

/datum/looping_sound/proc/stop(atom/remove_thing, skip_stop_sound = FALSE)
	if(remove_thing)
		output_atoms -= remove_thing
	var/was_dormant = !isnull(dormant_chunk_keys)
	leave_dormancy()
	if(!timerid)
		return
	if(was_dormant)
		skip_stop_sound = TRUE // Nobody was in range to hear it end.
	if(!skip_stop_sound)
		on_stop()
	deltimer(timerid)
	timerid = null
	started = FALSE

/datum/looping_sound/proc/sound_loop(starttime)
	if(QDELETED(src) || (max_loops && world.time >= starttime + mid_length * max_loops))
		stop()
		return
	if(!direct && !has_listener())
		enter_dormancy(starttime)
		return
	if(!chance || prob(chance))
		var/soundfile = get_sound(starttime)
		if(soundfile)
			play(soundfile)
	if(!timerid)
		timerid = addtimer(CALLBACK(src, PROC_REF(sound_loop), world.time), mid_length, TIMER_STOPPABLE | TIMER_LOOP)

/// TRUE if a player could hear this loop from any of its output atoms.
/datum/looping_sound/proc/has_listener()
	var/max_distance = (world.view + extra_range) * 2
	for(var/atom/thing as anything in output_atoms)
		var/turf/source_turf = get_turf(thing)
		if(source_turf && playsound_has_listener(source_turf, max_distance))
			return TRUE
	return FALSE

/// Stops the loop timer and waits for a player to enter a nearby chunk.
/// A slow recheck also runs, for sources that move or players that appear without moving.
/datum/looping_sound/proc/enter_dormancy(starttime)
	if(timerid)
		deltimer(timerid)
	dormant_starttime = starttime
	var/max_distance = (world.view + extra_range) * 2
	var/list/keys = list()
	for(var/atom/thing as anything in output_atoms)
		var/turf/source_turf = get_turf(thing)
		if(!source_turf)
			continue
		var/min_x = MOB_CHUNK_COORD(max(source_turf.x - max_distance, 1))
		var/max_x = MOB_CHUNK_COORD(min(source_turf.x + max_distance, world.maxx))
		var/min_y = MOB_CHUNK_COORD(max(source_turf.y - max_distance, 1))
		var/max_y = MOB_CHUNK_COORD(min(source_turf.y + max_distance, world.maxy))
		for(var/chunk_x in min_x to max_x)
			for(var/chunk_y in min_y to max_y)
				keys |= MOB_CHUNK_NUMERIC_KEY(source_turf.z, chunk_x, chunk_y)
	dormant_chunk_keys = keys
	SSsounds.subscribe_dormant_loop(src, keys)
	timerid = addtimer(CALLBACK(src, PROC_REF(wake_from_dormancy)), LOOPING_SOUND_DORMANT_RECHECK, TIMER_STOPPABLE)

/datum/looping_sound/proc/leave_dormancy()
	if(isnull(dormant_chunk_keys))
		return FALSE
	SSsounds.unsubscribe_dormant_loop(src, dormant_chunk_keys)
	dormant_chunk_keys = null
	return TRUE

/datum/looping_sound/proc/wake_from_dormancy()
	if(!leave_dormancy())
		return
	if(timerid)
		deltimer(timerid)
		timerid = null
	sound_loop(dormant_starttime)

/datum/looping_sound/proc/play(soundfile)
	var/list/atoms_cache = output_atoms
	var/sound/S = sound(soundfile)
	if(direct)
		S.channel = SSsounds.random_available_channel()
		S.volume = volume
	for(var/i in 1 to atoms_cache?.len)
		var/atom/thing = atoms_cache[i]
		if(direct)
			if(ismob(thing))
				var/mob/M = thing
				if(!M.check_sound_preference(pref_check))
					continue
			SEND_SOUND(thing, S)
		else
			playsound(thing, S, volume, vary, extra_range, falloff = falloff, ignore_walls = !opacity_check, preference = pref_check, volume_channel = volume_chan)

/datum/looping_sound/proc/get_sound(starttime, _mid_sounds)
	if(!_mid_sounds)
		. = mid_sounds
	else
		. = _mid_sounds
	while(!isfile(.) && !isnull(.))
		. = pickweight(.)

/datum/looping_sound/proc/on_start()
	var/start_wait = 1 // On TG this is 0, however it needs to be 1 to work around an issue.
	if(start_sound)
		play(start_sound)
		start_wait = start_length
	addtimer(CALLBACK(src, PROC_REF(sound_loop)), start_wait)

/datum/looping_sound/proc/on_stop()
	if(end_sound)
		play(end_sound)

#undef LOOPING_SOUND_DORMANT_RECHECK
