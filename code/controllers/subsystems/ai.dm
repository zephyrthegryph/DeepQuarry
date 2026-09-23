SUBSYSTEM_DEF(ai)
	name = "AI"
	priority = FIRE_PRIORITY_AI
	wait = 2 SECONDS
	flags = SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	dependencies = list(
		/datum/controller/subsystem/air,
		/datum/controller/subsystem/mobs
	)

	var/list/processing = list()
	var/list/currentrun = list()

	var/slept_mobs = 0
	var/list/process_z = list()
	var/deferred_brains = 0
	var/profile_cost = 0
	var/profile_calls = 0
	var/navigation_revision = 1

/datum/controller/subsystem/ai/proc/publish_navigation_change()
	navigation_revision++

/datum/controller/subsystem/ai/stat_entry(msg)
	msg = "P:[length(processing)] S:[slept_mobs] D:[deferred_brains] AI:[round(profile_cost, 0.1)]ms/[profile_calls]"
	return ..()

/datum/controller/subsystem/ai/fire(resumed = 0)
	if (!resumed)
		src.currentrun = processing.Copy()
		process_z.Cut()
		slept_mobs = 0
		deferred_brains = 0
		profile_cost = 0
		profile_calls = 0
		var/level = 1
		while(length(process_z) < length(GLOB.living_players_by_zlevel))
			process_z.len++
			process_z[level] = length(GLOB.living_players_by_zlevel[level])
			level++

	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun

	while(length(currentrun))
		var/datum/ai_brain/A = currentrun[length(currentrun)]
		--currentrun.len
		if(!A || QDELETED(A) || A.busy) // Doesn't exist or won't exist soon or not doing it this tick
			continue

		var/mob/living/L = A.holder
		if(!L?.loc)
			continue

		if(A.next_strategic_at > world.time)
			deferred_brains++
			continue
		if((get_z(L) && process_z[get_z(L)]) || !L.low_priority)
			var/profile_start = TICK_USAGE
			A.handle_strategicals()
			profile_cost += TICK_DELTA_TO_MS(TICK_USAGE - profile_start)
			profile_calls++
		else
			slept_mobs++
			A.set_stance(STANCE_IDLE)  // brain has set_stance as a no-op
		if(MC_TICK_CHECK)
			return

// --- Calm-brain hibernation on mob-chunk keys (reactor.md §9, S2) ---------------------------------

/// A calm brain stops strategic processing until a mob moves in a chunk within its vision
/// (REACT_KEY_MOB_CHUNK). FALSE if it has a threat, a behavior or a player.
/datum/ai_brain/proc/hibernate_calm()
	var/turf/T = get_turf(holder)
	if(!T || primary_threat || active_behavior_type || holder.client)
		return FALSE
	cancel_chunk_sleep()
	var/list/keys = list()
	for(var/cx in MOB_CHUNK_COORD(max(T.x - vision_range, 1)) to MOB_CHUNK_COORD(T.x + vision_range))
		for(var/cy in MOB_CHUNK_COORD(max(T.y - vision_range, 1)) to MOB_CHUNK_COORD(T.y + vision_range))
			keys += list(REACT_KEY_MOB_CHUNK, MOB_CHUNK_NUMERIC_KEY(T.z, cx, cy), REACT_CHUNK_ANY_MOB)
	react_sleep_tokens = SSreactor.sleep_on_keys(src, keys)
	manage_processing(0)
	return TRUE

/// Drops the chunk subscriptions without waking (Destroy, or before re-subscribing).
/datum/ai_brain/proc/cancel_chunk_sleep()
	if(react_sleep_tokens)
		SSreactor.cancel_keys(src, react_sleep_tokens)
		react_sleep_tokens = null

/// Wakes a hibernating brain now. No-op unless it sleeps on chunk keys.
/datum/ai_brain/proc/wake_from_chunks()
	if(!react_sleep_tokens)
		return
	cancel_chunk_sleep()
	if(QDELETED(src))
		return
	next_strategic_at = 0
	manage_processing(DQAI_PROCESSING)

/datum/ai_brain/on_react(reason, source, source_kind)
	if(reason & REACT_REASON_KEY)
		wake_from_chunks()

/// Asleep with a threat in hand: it should be awake.
/datum/ai_brain/react_sleep_violation()
	if(!react_sleep_tokens || (process_flags & DQAI_PROCESSING))
		return null
	if(primary_threat)
		return "hibernating with a primary threat"
	return null
