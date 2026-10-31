// ---- the default-look stamp (doc/rewrite/proposals/change_graph.md section 7, step 5) ----
//
// A fresh atom's first refresh is queued at creation (caps_init()) with DEP_CREATED beside DEP_ALL; any real mark clears the bit
// (refresh_mark()). The first fresh instance of a type that the drain refreshes records whether the type's default look is empty
// (type_look_default_empty()): it drew nothing, hides and grants no verbs, watches nothing, has no derived values, side effects or
// periodic work. For such a type a fresh instance's first refresh does nothing, so the stamp is the mapped appearance it already has:
// later instances are not queued at creation, and ones queued before the verdict (a map load) are dropped by the drain and by
// refresh_settle_created() at boot. A type whose default look is not empty keeps its forced first draw.

/// Type path -> TRUE (the default look is empty: no first draw) or FALSE (a first draw is kept). Absent: not sampled yet.
GLOBAL_LIST_EMPTY(type_look_stamp)
/// Fresh entities the stamp spared a first refresh (the draw-queue test and the boot log read it).
GLOBAL_VAR_INIT(type_look_stamp_skipped, 0)

/// Whether `D` (a fresh instance, just refreshed for the first time) shows that its type's default look is empty.
/proc/type_look_default_empty(datum/D)
	if(!isatom(D) || ismob(D))
		return FALSE
	var/atom/A = D
	var/flags = GLOB.type_derives_cache[A.type]
	if(isnull(flags) || (flags & (TYPE_DERIVES_PENDING | TYPE_DERIVES_SIDE | TYPE_DERIVES_DEPS)))
		return FALSE
	if(A.periodic_cadence || A.periodic_interval || LAZYLEN(A.open_tguis))
		return FALSE
	if(A.rx && (!isnull(A.rx.look_key) || A.rx.refresh_hidden_verbs || A.rx.refresh_granted_verbs))
		return FALSE
	if(capability_data(A)?[/datum/cap_engine_state])
		return FALSE // it watches something or flashes: not a look the mapped appearance stands for
	return TRUE

/// TRUE when a fresh `D` of a stamped type needs no first refresh (its type's verdict is in and its default look is empty).
/proc/type_look_stamped(datum/D)
	if(!GLOB.type_look_stamp[D.type] || D.periodic_cadence || D.periodic_interval || LAZYLEN(D.open_tguis))
		return FALSE
	var/flags = GLOB.type_derives_cache[D.type]
	return !isnull(flags) && !(flags & TYPE_DERIVES_PENDING)

/// Records the stamp from a fresh instance's first refresh, once per type.
/proc/type_look_stamp_record(datum/D)
	if(isnull(GLOB.type_look_stamp[D.type]))
		GLOB.type_look_stamp[D.type] = type_look_default_empty(D)

/// Boot (after every system's members are ready): one fresh sample per type still waiting for a verdict is refreshed now, then every
/// queued fresh instance of a type whose default look is empty leaves the queue. A map load queues every atom before any drain has run
/// (310 k space turfs on the station map), and a clientless world does not run the presentation lane until someone connects.
/proc/refresh_settle_created()
	var/start = REALTIMEOFDAY
	var/list/Q = GLOB.refresh_queue
	var/before = length(Q)
	var/list/sampled = list()
	for(var/i in 1 to length(Q))
		var/datum/D = Q[i]
		if(isnull(D) || !(D.refresh_queued & DEP_CREATED) || sampled[D.type] || !isnull(GLOB.type_look_stamp[D.type]) || QDELETED(D))
			continue
		sampled[D.type] = TRUE
		var/pending = D.refresh_queued & ~DEP_CREATED
		var/bits = D.refresh_bits
		D.refresh_queued = 0
		D.refresh_bits = 0
		if(!refresh_wanted_queued(D))
			continue
		try
			refresh_one(D, bits, pending)
		catch(var/exception/e)
			stack_trace("refresh of [D.type]: [e] ([e.file]:[e.line])")
			continue
		type_look_stamp_record(D)
	var/list/kept = list()
	var/skipped = 0
	for(var/datum/D as anything in Q)
		if(isnull(D) || !D.refresh_queued)
			continue
		if(D.refresh_queued & DEP_CREATED && type_look_stamped(D))
			D.refresh_queued = 0
			D.refresh_bits = 0
			skipped++
			continue
		kept += D
	Q.Cut()
	Q += kept
	GLOB.type_look_stamp_skipped += skipped
	log_world("refresh settle: [before] queued at boot, [length(sampled)] type(s) sampled, [skipped] fresh atom(s) dropped (empty default look), [length(Q)] left, [(REALTIMEOFDAY - start) * 100] ms")

/// The queued refreshes within a screen of a client, run now and ahead of the rest of the backlog: a player who joins while the map's first draws
/// are still draining sees what is around them drawn at once. `turfs` defaults to every client's turf. Returns how many it ran. The entry the
/// atom leaves in the queue is a stale duplicate the drain skips.
/proc/refresh_drain_near(list/turfs = refresh_client_turfs())
	. = 0
	if(!length(GLOB.refresh_queue) || !length(turfs))
		return
	for(var/turf/where as anything in turfs)
		for(var/atom/A as anything in range(world.view + 2, where))
			var/pending = A.refresh_queued
			if(!pending || QDELETED(A))
				continue
			var/fresh = pending & DEP_CREATED
			pending &= ~DEP_CREATED
			var/bits = A.refresh_bits
			A.refresh_queued = 0
			A.refresh_bits = 0
			if(fresh && type_look_stamped(A))
				GLOB.type_look_stamp_skipped++
				continue
			if(!refresh_wanted_queued(A))
				continue
			try
				refresh_one(A, bits, pending)
				if(fresh)
					type_look_stamp_record(A)
			catch(var/exception/e)
				stack_trace("near refresh of [A.type]: [e] ([e.file]:[e.line])")
			.++
	if(.)
		GLOB.refresh_near_drawn += .

/// Queued first draws that ran ahead of the backlog because a client was near (logged with the periodic look stats).
GLOBAL_VAR_INIT(refresh_near_drawn, 0)
