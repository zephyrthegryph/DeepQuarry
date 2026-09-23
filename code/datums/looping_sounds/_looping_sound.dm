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
/// How often a dormant loop rechecks for listeners without a chunk wake
/// (a moving source, or a player who appears without moving).
#define LOOPING_SOUND_DORMANT_RECHECK (10 SECONDS)

/**
 * A looping sound runs on SSreactor (reactor.md §9, Q5): each loop is a REACT_AT timer, and a
 * loop nobody can hear parks on the player chunk keys (REACT_KEY_MOB_CHUNK, REACT_CHUNK_PLAYER) around it until a player
 * moves into range (with a slow recheck timer).
 */
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

	var/started
	/// TRUE from start() until stop(): the loop is waiting to start, looping or dormant.
	var/tmp/running = FALSE
	/// The pending REACT_AT: the next loop, the start delay or the dormant recheck.
	var/tmp/loop_token
	/// world.time of the first loop, so max_loops counts from the real start.
	var/tmp/loop_starttime
	/// Player chunk tokens while nobody can hear the loop; null while it is looping (Q5).
	var/tmp/list/dormant_chunk_tokens

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
	if(running)
		return
	if(skip_start_sound && (!exclusive && !started)) // Skip start sounds optionally, check if we're exclusive AND started already
		running = TRUE
		started = TRUE
		sound_loop()
		return
	if(exclusive && started) // Prevents a sound from starting multiple times
		return // Don't start this loop.
	running = TRUE
	on_start()
	started = TRUE

/datum/looping_sound/proc/stop(atom/remove_thing, skip_stop_sound = FALSE)
	if(remove_thing)
		output_atoms -= remove_thing
	if(!running)
		return
	if(leave_dormancy())
		skip_stop_sound = TRUE // Nobody was in range to hear it end.
	if(!skip_stop_sound)
		on_stop()
	cancel_loop_timer()
	running = FALSE
	started = FALSE
	loop_starttime = null

/datum/looping_sound/proc/cancel_loop_timer()
	if(!isnull(loop_token))
		REACT_CANCEL(src, loop_token)
		loop_token = null

/datum/looping_sound/on_react(reason, source, source_kind)
	if(!running)
		return
	if(dormant_chunk_tokens)
		wake_from_dormancy(reason & REACT_REASON_TIMER)
	else if(reason & REACT_REASON_TIMER)
		loop_token = null
		sound_loop()

/datum/looping_sound/react_sleep_violation()
	if(running && isnull(loop_token) && !dormant_chunk_tokens)
		return "running with no loop timer and no chunk keys"
	if(dormant_chunk_tokens && isnull(loop_token))
		return "dormant without its recheck timer"
	return null

/datum/looping_sound/proc/sound_loop()
	if(QDELETED(src) || !running)
		return
	if(isnull(loop_starttime))
		loop_starttime = world.time
	if(max_loops && world.time >= loop_starttime + mid_length * max_loops)
		stop()
		return
	if(!direct && !has_listener())
		enter_dormancy()
		return
	if(!chance || prob(chance))
		var/soundfile = get_sound(loop_starttime)
		if(soundfile)
			play(soundfile)
	cancel_loop_timer()
	loop_token = REACT_AT(src, world.time + mid_length)

/// TRUE if a player could hear this loop from any of its output atoms.
/datum/looping_sound/proc/has_listener()
	var/max_distance = (world.view + extra_range) * 2
	for(var/atom/thing as anything in output_atoms)
		var/turf/source_turf = get_turf(thing)
		if(source_turf && playsound_has_listener(source_turf, max_distance))
			return TRUE
	return FALSE

/// Stops looping and waits on the player chunk keys in hearing range, with a slow recheck.
/datum/looping_sound/proc/enter_dormancy()
	cancel_loop_timer()
	leave_dormancy()
	var/max_distance = (world.view + extra_range) * 2
	var/list/tokens = list()
	var/list/seen = list()
	for(var/atom/thing as anything in output_atoms)
		var/turf/source_turf = get_turf(thing)
		if(!source_turf || seen[source_turf])
			continue
		seen[source_turf] = TRUE
		tokens += SSreactor.subscribe_player_chunks(src, source_turf, max_distance)
	dormant_chunk_tokens = tokens
	loop_token = REACT_AT(src, world.time + LOOPING_SOUND_DORMANT_RECHECK)

/// Drops the chunk keys. TRUE if the loop was dormant.
/datum/looping_sound/proc/leave_dormancy()
	if(isnull(dormant_chunk_tokens))
		return FALSE
	SSreactor.unsubscribe_player_chunks(src, dormant_chunk_tokens)
	dormant_chunk_tokens = null
	return TRUE

/// A player moved nearby, or the recheck fired. A chunk wake with still nobody in range
/// stays dormant on the same keys; the recheck rebuilds them (the source may have moved).
/datum/looping_sound/proc/wake_from_dormancy(recheck)
	if(!recheck && !direct && !has_listener())
		return
	leave_dormancy()
	cancel_loop_timer()
	sound_loop()

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
	cancel_loop_timer()
	loop_token = REACT_AT(src, world.time + start_wait)

/datum/looping_sound/proc/on_stop()
	if(end_sound)
		play(end_sound)

#undef LOOPING_SOUND_DORMANT_RECHECK
