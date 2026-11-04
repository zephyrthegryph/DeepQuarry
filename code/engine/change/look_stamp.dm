// ---- the default-look stamp (doc/rewrite/proposals/change_graph.md section 7, step 5) ----
//
// A fresh atom's first refresh is queued at creation (caps_init()) with DEP_CREATED beside DEP_ALL; any real mark clears the bit
// (refresh_mark()). The first fresh instance of a type that the drain refreshes records whether the type's default look is empty
// (type_look_default_empty()): it drew nothing, hides and grants no verbs, watches nothing, has no derived values, side effects or
// periodic work. For such a type a fresh instance's first refresh does nothing, so the stamp is the mapped appearance it already has:
// later instances are not queued at creation, and ones queued before the verdict (a map load) are dropped by the drain and by
// refresh_settle_created() at boot. A type whose default look is not empty keeps its forced first draw.

/// How often the parked backlog is scanned around each client (lazy first draw, below).
#define REFRESH_NEAR_INTERVAL (0.5 SECONDS)
/// How many levels of stacked open space a client's view is followed down (refresh_drain_near()).
#define REFRESH_THROUGH_DEPTH 8

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
		var/gameplay_before = isatom(D) ? look_gameplay_state(D) : null
		try
			refresh_one(D, bits, pending)
		catch(var/exception/e)
			dq_report_caught(e, "refresh of [D.type]")
			continue
		type_look_stamp_record(D)
		if(!isnull(gameplay_before))
			look_lazy_record(D, gameplay_before)
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
	if(!length(GLOB.refresh_queue))
		// Only parked first draws wait: scan on an interval, not every tick.
		if(!GLOB.refresh_has_parked || !COOLDOWN_FINISHED(GLOB, refresh_near_next))
			return
		COOLDOWN_START(GLOB, refresh_near_next, REFRESH_NEAR_INTERVAL)
	if(!length(turfs))
		return
	// A turf that shows the level below it (open space) shows what is on that turf, and so on down: those are seen too, from the one tile.
	var/list/through = list()
	for(var/turf/where as anything in turfs)
		for(var/atom/A as anything in range(turfs[where] || (world.view + 2), where))
			. += refresh_draw_seen(A)
			if(isturf(A))
				var/turf/seen = A
				var/turf/below = seen.seen_through()
				if(below)
					through[below] = TRUE
	for(var/i in 1 to REFRESH_THROUGH_DEPTH)
		var/list/next = list()
		for(var/turf/where as anything in through)
			for(var/atom/A as anything in range(0, where))
				. += refresh_draw_seen(A)
			var/turf/below = where.seen_through()
			if(below && !through[below])
				next[below] = TRUE
		if(!length(next))
			break
		through = next
	if(.)
		GLOB.refresh_near_drawn += .

/// A queued or parked first draw of `A`, run now because a client sees it. Returns 1 when it ran.
/proc/refresh_draw_seen(atom/A)
	var/pending = A.refresh_queued
	if(!pending || QDELETED(A))
		return 0
	var/parked = pending & DEP_PARKED
	if(parked)
		pending = DEP_ALL | DEP_CREATED // the first refresh it owes
	var/fresh = pending & DEP_CREATED
	pending &= ~(DEP_CREATED | DEP_PARKED)
	var/bits = A.refresh_bits
	A.refresh_queued = 0
	A.refresh_bits = 0
	if(fresh && type_look_stamped(A))
		GLOB.type_look_stamp_skipped++
		return 0
	if(!refresh_wanted_queued(A))
		return 0
	try
		refresh_one(A, bits, pending)
		if(fresh)
			type_look_stamp_record(A)
	catch(var/exception/e)
		dq_report_caught(e, "near refresh of [A.type]")
	if(parked)
		GLOB.refresh_parked_near++
	return 1

/// Queued first draws that ran ahead of the backlog because a client was near (logged with the periodic look stats).
GLOBAL_VAR_INIT(refresh_near_drawn, 0)

/// Boot: draws every first refresh the settle left queued, with no budget (nobody is connected to wait on it, and the same draws would otherwise
/// run in the presentation lane for a minute after "Initializations complete", costing the first players their frame time). One line per pass
/// (queued, left, milliseconds) so a slow or stuck boot shows where it is.
/proc/refresh_boot_drain()
	var/start = REALTIMEOFDAY
	var/before = length(GLOB.refresh_queue)
	var/passes = 0
	while(length(GLOB.refresh_queue) && passes < 20)
		passes++
		var/queued = length(GLOB.refresh_queue)
		var/pass_start = REALTIMEOFDAY
		refresh_drain(null)
		log_world("refresh boot drain pass [passes]: [queued] queued, [length(GLOB.refresh_queue)] left, [(REALTIMEOFDAY - pass_start) * 100] ms")
	world.presentation_flush()
	log_world("refresh boot drain: [before] queued, [length(GLOB.refresh_queue)] left after [passes] pass(es), [(REALTIMEOFDAY - start) * 100] ms")

// ---- lazy first draw (the parked backlog) ----
//
// A server leaves the map's first draws to the presentation lane (host.dm). Most of them are of atoms nobody looks at before something else marks them, so
// the ones whose first draw is purely a picture do not wait in the queue at all: they are parked (DEP_PARKED), draw when a client comes near
// (refresh_drain_near()) and draw, with everything else they owe, the moment anything marks them (refresh_mark()). A type qualifies when its sampled first
// draw changed nothing but the look (no light, opacity, density or verbs) and the type derives nothing else (no values, side effects, capabilities that
// watch, periodic work, windows). The verdict comes from one fresh instance per type, as the default-look stamp's does.

/// Type path -> TRUE: the sampled first draw changed only the look. Absent or FALSE: the type's first draws stay queued.
GLOBAL_LIST_EMPTY(type_look_lazy)
/// First draws parked at boot, and the ones drawn since because a client came near.
GLOBAL_VAR_INIT(refresh_parked, 0)
GLOBAL_VAR_INIT(refresh_parked_near, 0)
/// Whether anything was ever parked: refresh_drain_near() has work with an empty queue only then.
GLOBAL_VAR_INIT(refresh_has_parked, FALSE)
/// The next time refresh_drain_near() scans around the clients while the queue is empty.
GLOBAL_VAR_INIT(refresh_near_next, 0)

/// What a draw must leave alone for the atom's first draw to be deferrable: everything that is not the picture but still shapes play.
/proc/look_gameplay_state(atom/A)
	return "[A.luminosity]|[A.opacity]|[A.density]|[A.look_light_key()]|[length(A.verbs)]"

/// After a fresh instance's first refresh: records the type's lazy verdict (once per type) from whether the refresh changed only its look.
/proc/look_lazy_record(atom/A, gameplay_before)
	if(!isnull(GLOB.type_look_lazy[A.type]))
		return
	GLOB.type_look_lazy[A.type] = look_cosmetic_only(A) && look_gameplay_state(A) == gameplay_before

/// Whether `A` derives nothing but a look: the type_look_default_empty() test, minus the look.
/proc/look_cosmetic_only(atom/A)
	if(ismob(A))
		return FALSE
	var/flags = GLOB.type_derives_cache[A.type]
	if(isnull(flags) || (flags & (TYPE_DERIVES_PENDING | TYPE_DERIVES_SIDE | TYPE_DERIVES_DEPS)))
		return FALSE
	if(A.periodic_cadence || A.periodic_interval || LAZYLEN(A.open_tguis))
		return FALSE
	if(A.rx && (A.rx.refresh_hidden_verbs || A.rx.refresh_granted_verbs))
		return FALSE
	if(capability_data(A)?[/datum/cap_engine_state])
		return FALSE
	return TRUE

/// Whether a fresh queued `A` may be parked: its type's verdict is lazy and this instance has nothing the verdict did not see.
/proc/look_lazy_ok(atom/A)
	if(!GLOB.type_look_lazy[A.type] || A.periodic_cadence || A.periodic_interval || LAZYLEN(A.open_tguis))
		return FALSE
	return !ismob(A)

/// Boot, after refresh_settle_created(): every fresh queued atom of a lazy type leaves the queue, parked. Returns how many; logged with the milliseconds.
/proc/refresh_park_backlog()
	var/start = REALTIMEOFDAY
#ifdef BENCHMARK
	if(text2num(world.params?["bench_no_park"]))
		return 0 // --arg=no_park=1: the same boot without parking, for a before/after
#endif
	var/list/Q = GLOB.refresh_queue
	var/list/kept = list()
	var/parked = 0
	for(var/datum/D as anything in Q)
		if(isnull(D) || !D.refresh_queued || D.refresh_queued == DEP_PARKED)
			continue // (a stale duplicate of an atom already parked leaves too)
		// Fresh and untouched: only the creation mark beside DEP_ALL (a real mark clears the creation mark).
		if((D.refresh_queued & DEP_CREATED) && isatom(D) && look_lazy_ok(D))
			D.refresh_queued = DEP_PARKED
			D.refresh_bits = 0
			parked++
			continue
		kept += D
	Q.Cut()
	Q += kept
	GLOB.refresh_parked += parked
	if(parked)
		GLOB.refresh_has_parked = TRUE
	log_world("refresh park: [parked] first draw(s) parked for a client to come near, [length(Q)] kept queued, [(REALTIMEOFDAY - start) * 100] ms")
	return parked
