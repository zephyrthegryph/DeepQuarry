// ---- the default look: what a fresh atom already shows needs no draw (doc/rewrite/draw_on_change.md section 4) ----
//
// A fresh atom's first refresh is queued at creation (caps_init()) with DEP_CREATED beside DEP_ALL; any real mark clears the bit (refresh_mark()). An atom
// still carrying it is in its type's default state. The first fresh instance of a type that is refreshed records whether the type's default look is empty
// (type_look_default_empty()): it drew nothing, hides and grants no verbs, watches nothing, has no derived values, side effects or periodic work. For such a
// type a fresh instance's first refresh does nothing, so the stamp is the mapped appearance it already has: later instances are not queued at creation,
// and ones queued before the verdict (a map load) are dropped when the boot settles (refresh_settle_created()) and by the drain. A type whose default look
// is not empty keeps its first draw, which the appearance cache makes cheap (look_cache.dm).
//
// A type the generated declarations say derives nothing (no draw, no verbs, no capabilities, no values) is not queued at all (caps_init()). The verdict of
// the others is learned by sampling, once per boot: nothing is written to disk. An instance of a type whose draw is keyed by the cache (look_cache_key())
// is stamped only while its inputs are the sample's (type_look_stamped()): a fresh instance a map var edit changed is drawn.

/// Type path -> TRUE (the default look is empty: no first draw) or FALSE (a first draw is kept). Absent: not sampled yet.
GLOBAL_LIST_EMPTY(type_look_stamp)
/// Type path -> the cache key of the sample's inputs, for a stamped type the cache can key (look_cache_key()). Absent: any instance is stamped.
GLOBAL_LIST_EMPTY(type_look_stamp_key)
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
	if(LAZYLEN(A.open_tguis))
		return FALSE
	if(A.rx && (!isnull(A.rx.look_key) || A.rx.refresh_hidden_verbs || A.rx.refresh_granted_verbs))
		return FALSE
	if(capability_data(A)?[/datum/cap_engine_state])
		return FALSE // it watches something or flashes: not a look the mapped appearance stands for
	return TRUE

/// TRUE when a fresh `D` of a stamped type needs no first refresh: its type's verdict is in and its default look is empty, and (for a type whose draw the
/// cache keys) its inputs are the sample's.
/proc/type_look_stamped(datum/D)
	if(!GLOB.type_look_stamp[D.type] || LAZYLEN(D.open_tguis))
		return FALSE
	var/flags = GLOB.type_derives_cache[D.type]
	if(isnull(flags) || (flags & TYPE_DERIVES_PENDING))
		return FALSE
	var/sample_key = GLOB.type_look_stamp_key[D.type]
	if(sample_key && isatom(D) && look_cache_key(D, FALSE) != sample_key)
		return FALSE
	return TRUE

/// Records the stamp from a fresh instance's first refresh, once per type.
/proc/type_look_stamp_record(datum/D)
	if(!isnull(GLOB.type_look_stamp[D.type]))
		return
	var/stamped = type_look_default_empty(D)
	GLOB.type_look_stamp[D.type] = stamped
	if(stamped && isatom(D))
		var/key = look_cache_key(D, FALSE)
		if(key)
			GLOB.type_look_stamp_key[D.type] = key

/// Boot (after every system's members are ready): one fresh sample per type still waiting for a verdict is refreshed now, then every queued fresh instance
/// of a type whose default look is empty leaves the queue, and each held atom (boot_created_hold()) is released by its type's verdict. What is left to draw
/// goes to the draw queue (draw_file()) or stays in the refresh queue when it has outputs besides its look.
/proc/refresh_settle_created()
	var/start = REALTIMEOFDAY
	var/list/Q = GLOB.refresh_queue
	var/before = length(Q)
	log_world("refresh queue by kind at boot, before the settle: [refresh_kind_census(Q)]")
	var/list/sampled = list()
	for(var/i in 1 to length(Q))
		var/datum/D = Q[i]
		if(isnull(D) || sampled[D.type] || QDELETED(D) || !D.refresh_queued)
			continue
		// A fresh instance samples the verdict. A type every instance of which was written during init has none left on its creation mark: it is drawn
		// with the rest.
		if(!((D.refresh_queued & DEP_CREATED) && isnull(GLOB.type_look_stamp[D.type])))
			continue
		sampled[D.type] = TRUE
		var/pending = D.refresh_queued & ~DEP_CREATED
		var/bits = D.refresh_bits
		D.refresh_queued = 0
		D.refresh_bits = 0
		refresh_queue_drop(D)
		if(!refresh_wanted_queued(D))
			continue
		try
			refresh_one(D, bits, pending)
		catch(var/exception/e)
			dq_report_caught(e, "refresh of [D.type]")
			continue
		type_look_stamp_record(D)
	var/sampled_at = REALTIMEOFDAY
	var/list/kept = list()
	var/skipped = 0
	var/filed = 0
	for(var/datum/D as anything in Q)
		if(isnull(D) || !D.refresh_queued)
			continue
		if((D.refresh_queued & DEP_CREATED) && type_look_stamped(D))
			D.refresh_queued = 0
			D.refresh_bits = 0
			skipped++
			continue
		if(isatom(D) && !refresh_eager(D))
			filed++ // its look is all it owes: the draw queue takes it, by the chunk it stands in
			draw_file(D)
			continue
		kept += D
	refresh_queue_replace(kept)
	var/walked_at = REALTIMEOFDAY
	skipped += boot_created_release() // the atoms held by type while the map loaded: an empty default look owes nothing, the rest are marked now
	log_world("refresh settle phases (ms): sample [(sampled_at - start) * 100], queue walk [(walked_at - sampled_at) * 100], held release [(REALTIMEOFDAY - walked_at) * 100]")
	GLOB.type_look_stamp_skipped += skipped
	log_world("refresh queue by kind after the settle: [refresh_kind_census(Q)]")
	log_world("refresh settle: [before] queued at boot, [length(sampled)] type(s) sampled, [skipped] fresh atom(s) dropped (empty default look), [filed] first draw(s) filed by chunk, [length(Q)] left in the refresh queue, [draw_depth()] filed in all, [(REALTIMEOFDAY - start) * 100] ms")

/// Boot: draws everything still owed, with no budget (a test world reads looks right after boot, and nobody is connected to wait on a server's boot).
/// One line per pass (queued, left, milliseconds) so a slow or stuck boot shows where it is.
/proc/refresh_boot_drain()
	var/start = REALTIMEOFDAY
	var/before = length(GLOB.refresh_queue) + draw_depth()
	var/passes = 0
	while((length(GLOB.refresh_queue) || length(GLOB.draw_buckets)) && passes < 20)
		passes++
		var/queued = length(GLOB.refresh_queue) + draw_depth()
		var/pass_start = REALTIMEOFDAY
		refresh_drain(null)
		draw_drain(null)
		log_world("refresh boot drain pass [passes]: [queued] queued, [length(GLOB.refresh_queue) + draw_depth()] left, [(REALTIMEOFDAY - pass_start) * 100] ms")
	world.presentation_flush()
	log_world("refresh boot drain: [before] queued, [length(GLOB.refresh_queue) + draw_depth()] left after [passes] pass(es), [(REALTIMEOFDAY - start) * 100] ms")

/// The kinds of work queued in `Q`, as one line: entries whose live pending bits are look only, values, effects, UI/periodic, and entries with nothing live
/// (a mark that does nothing). Counted per entry, an entry counts under each kind it holds; `datums` is the part of `entries` that are not atoms.
/proc/refresh_kind_census(list/Q)
	var/entries = 0
	var/datums = 0
	var/look = 0
	var/values = 0
	var/effects = 0
	var/windows = 0
	var/dead = 0
	for(var/datum/D as anything in Q)
		if(isnull(D) || REFRESH_IDLE(D))
			continue
		entries++
		if(!isatom(D))
			datums++
		var/live = (D.refresh_queued & ~DEP_CREATED) & refresh_live_outputs(D)
		if(!live)
			dead++
			continue
		if(live & DEP_DRAW)
			look++
		if(live & DEP_VALUES)
			values++
		if(live & (DEP_PUSH | DEP_LEGACY))
			effects++
		if(live & DEP_UI)
			windows++
	return "[entries] entries ([datums] datums): look [look], values [values], effects [effects], ui [windows], nothing live [dead]"

// ---- the boot hold: the fresh atoms of a map load wait by type for their type's verdict ----
//
// A type's look verdict (type_look_stamp) is learned from one sampled first draw. Before it is known, a map load used to queue every fresh atom for its
// first refresh (519 k at a full-map boot), and the settle walked them all to drop the 368 k of types whose default look is empty. Now the first fresh
// instance of a type with no verdict yet is queued as its sample, and every later one is held out of every queue (DF_BOOT_HELD), in its type's bucket.
// refresh_settle_created() decides each bucket from the sample: an empty default look owes nothing; any other is marked for its first refresh as
// before. A write to a held atom marks nothing: the settle draws it once, with what it was written, never an atom at a time.

/// type -> the fresh atoms of a map load held for the type's verdict (boot_created_hold()). Empty outside a load's settle window.
GLOBAL_LIST_EMPTY(boot_created_buckets)
/// type -> TRUE once a fresh instance of the type has been queued as its sample during a map load.
GLOBAL_LIST_EMPTY(boot_created_sampled)
/// TRUE once the boot settle ran: a later map load (an expedition, a template) queues its fresh atoms as before, since no settle follows it.
GLOBAL_VAR_INIT(boot_created_settled, FALSE)
/// Fresh atoms held by type, and how many of them the settle released without a draw.
GLOBAL_VAR_INIT(boot_created_held, 0)
GLOBAL_VAR_INIT(boot_created_dropped, 0)

/// caps_init(), for a fresh `A` not yet queued: TRUE when it is held instead of queued (made by the boot map load, a type with no verdict, its sample
/// already queued). FALSE queues it as before; the first such instance of a type is recorded as the sample.
/// Only an atom on the map (a turf, or anything with a turf under it) waits: a client's HUD (its plane masters and fullscreen overlays, which live in
/// nullspace) made while the server boots, for a player who connects early, is drawn at once.
/proc/boot_created_hold(atom/A)
	if(GLOB.boot_created_settled || ismob(A) || isnull(get_turf(A)) || !materialization_host().frame_running())
		return FALSE // the cheap tests first: this runs for every atom created at boot
	if(!isnull(GLOB.type_look_stamp[A.type]))
		return FALSE
	if(!GLOB.boot_created_sampled[A.type])
		GLOB.boot_created_sampled[A.type] = TRUE
		return FALSE
	var/list/bucket = GLOB.boot_created_buckets[A.type]
	if(!bucket)
		bucket = list()
		GLOB.boot_created_buckets[A.type] = bucket
	bucket += A
	A.datum_flags |= DF_BOOT_HELD
	GLOB.boot_created_held++
	return TRUE

/// refresh_forget(): a held atom is destroyed before the settle: it leaves its bucket (it was appended last, so the search from the end is short).
/proc/boot_created_forget(datum/D)
	D.datum_flags &= ~DF_BOOT_HELD
	var/list/bucket = GLOB.boot_created_buckets?[D.type]
	bucket?.Remove(D)

/// refresh_settle_created(), once the samples are drawn: each bucket by its type's verdict. Returns how many held atoms owed nothing.
/proc/boot_created_release()
	var/list/buckets = GLOB.boot_created_buckets
	GLOB.boot_created_buckets = list()
	GLOB.boot_created_sampled = list()
	GLOB.boot_created_settled = TRUE
	. = 0
	for(var/type in buckets)
		var/list/bucket = buckets[type]
		var/empty = GLOB.type_look_stamp[type]
		for(var/atom/A as anything in bucket)
			if(QDELETED(A) || !(A.datum_flags & DF_BOOT_HELD))
				continue // deleted, or released already
			A.datum_flags &= ~DF_BOOT_HELD
			if(empty && type_look_stamped(A))
				.++
				continue
			refresh_mark(A, DEP_ALL)
			A.refresh_queued |= DEP_CREATED
	GLOB.boot_created_dropped += .
