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
	/// MOB_CHUNK_NUMERIC_KEY -> weakrefs of calm brains. Movement into or out
	/// of a watched chunk wakes only nearby brains.
	var/alist/chunk_subscribers
	var/list/sleeping_brains = list()
	var/navigation_revision = 1

/datum/controller/subsystem/ai/New()
	chunk_subscribers = alist()
	return ..()

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

/datum/controller/subsystem/ai/proc/hibernate_calm_brain(datum/ai_brain/A)
	var/turf/T = get_turf(A?.holder)
	if(!T || A.primary_threat || A.active_behavior_type || A.holder.client)
		return FALSE
	var/datum/weakref/WR = WEAKREF(A)
	A.sleeping_reference = WR.reference
	var/min_chunk_x = FLOOR(max(T.x - A.vision_range - 1, 0), CHUNK_SIZE) / CHUNK_SIZE
	var/max_chunk_x = FLOOR(T.x + A.vision_range - 1, CHUNK_SIZE) / CHUNK_SIZE
	var/min_chunk_y = FLOOR(max(T.y - A.vision_range - 1, 0), CHUNK_SIZE) / CHUNK_SIZE
	var/max_chunk_y = FLOOR(T.y + A.vision_range - 1, CHUNK_SIZE) / CHUNK_SIZE
	var/list/keys = list()
	for(var/cx in min_chunk_x to max_chunk_x)
		for(var/cy in min_chunk_y to max_chunk_y)
			var/key = MOB_CHUNK_NUMERIC_KEY(T.z, cx, cy)
			keys += key
			var/list/subscribers = chunk_subscribers[key]
			if(!subscribers)
				subscribers = list()
				chunk_subscribers[key] = subscribers
			subscribers[WR.reference] = WR
	sleeping_brains[WR.reference] = keys
	A.manage_processing(0)
	return TRUE

/datum/controller/subsystem/ai/proc/wake_brain(datum/weakref/WR)
	var/list/keys = sleeping_brains[WR?.reference]
	if(!keys)
		return
	for(var/key in keys)
		var/list/subscribers = chunk_subscribers[key]
		subscribers?.Remove(WR.reference)
		if(subscribers && !length(subscribers))
			chunk_subscribers.Remove(key)
	sleeping_brains.Remove(WR.reference)
	var/datum/ai_brain/A = WR.resolve()
	if(A && !QDELETED(A))
		A.sleeping_reference = null
		A.next_strategic_at = 0
		A.manage_processing(DQAI_PROCESSING)

/datum/controller/subsystem/ai/proc/forget_brain(datum/ai_brain/A)
	var/reference = A?.sleeping_reference
	if(!reference)
		return
	var/list/keys = sleeping_brains[reference]
	for(var/key in keys)
		var/list/subscribers = chunk_subscribers[key]
		subscribers?.Remove(reference)
		if(subscribers && !length(subscribers))
			chunk_subscribers.Remove(key)
	sleeping_brains.Remove(reference)
	A.sleeping_reference = null

/datum/controller/subsystem/ai/proc/publish_mob_chunk(atom/location)
	// Nothing sleeping means nothing to wake; skip the turf lookup (Q12).
	if(!length(chunk_subscribers))
		return
	var/turf/T = get_turf(location)
	if(!T)
		return
	var/key = MOB_CHUNK_NUMERIC_KEY(T.z, MOB_CHUNK_COORD(T.x), MOB_CHUNK_COORD(T.y))
	var/list/subscribers = chunk_subscribers[key]
	if(!length(subscribers))
		return
	for(var/subscriber_key in subscribers.Copy())
		wake_brain(subscribers[subscriber_key])
