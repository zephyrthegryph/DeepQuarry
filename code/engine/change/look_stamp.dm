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
	log_world("refresh queue by kind at boot, before the settle: [refresh_kind_census(Q)]")
	var/list/sampled = list()
	for(var/i in 1 to length(Q))
		var/datum/D = Q[i]
		if(isnull(D) || sampled[D.type] || QDELETED(D) || !D.refresh_queued)
			continue
		// A fresh instance samples both verdicts. A type every instance of which was written during init (windows, pipes, lattices) has none left on its
		// creation mark: one written instance samples the lazy verdict alone (its draw is not the type's default look, so it says nothing of the stamp).
		var/fresh_sample = (D.refresh_queued & DEP_CREATED) && isnull(GLOB.type_look_stamp[D.type])
		if(!fresh_sample && (!isatom(D) || !isnull(GLOB.type_look_lazy[D.type])))
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
		if(fresh_sample)
			type_look_stamp_record(D)
		if(!isnull(gameplay_before))
			look_lazy_record(D, gameplay_before)
	var/sampled_at = REALTIMEOFDAY
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
	refresh_queue_replace(kept)
	var/walked_at = REALTIMEOFDAY
	skipped += boot_created_release() // the atoms held by type while the map loaded: an empty default look owes nothing, the rest are queued now
	look_verdicts_save()
	log_world("refresh settle phases (ms): sample [(sampled_at - start) * 100], queue walk [(walked_at - sampled_at) * 100], held release [(REALTIMEOFDAY - walked_at) * 100]")
	GLOB.type_look_stamp_skipped += skipped
	log_world("refresh queue by kind after the settle: [refresh_kind_census(Q)]")
	log_world("refresh settle: [before] queued at boot, [length(sampled)] type(s) sampled, [skipped] fresh atom(s) dropped (empty default look), [length(Q)] left, [(REALTIMEOFDAY - start) * 100] ms")

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
// (interest_enter(), interest.dm) and draw, with everything else they owe, the moment anything marks them (refresh_mark()). A type qualifies when its sampled first
// draw changed nothing but the look (no light, opacity, density or verbs) and the type derives nothing else (no values, side effects, capabilities that
// watch, periodic work, windows). The verdict comes from one fresh instance per type, as the default-look stamp's does.

/// Type path -> TRUE: the sampled first draw changed only the look. Absent or FALSE: the type's first draws stay queued.
GLOBAL_LIST_EMPTY(type_look_lazy)
/// First draws parked at boot, and the ones drawn since because a client came near.
GLOBAL_VAR_INIT(refresh_parked, 0)
GLOBAL_VAR_INIT(refresh_parked_near, 0)

/// What a draw must leave alone for the atom's first draw to be deferrable: everything that is not the picture but still shapes play.
/proc/look_gameplay_state(atom/A)
	return "[A.luminosity]|[A.opacity]|[A.density]|[A.look_light_key()]|[length(A.verbs)]"

/// Type path -> why its first draws stay queued (absent for a lazy type): the rule that excluded it, for the park census.
GLOBAL_LIST_EMPTY(type_look_lazy_why)

/// After a fresh instance's first refresh: records the type's lazy verdict (once per type) from whether the refresh changed only its look.
/proc/look_lazy_record(atom/A, gameplay_before)
	if(!isnull(GLOB.type_look_lazy[A.type]))
		return
	var/why = look_lazy_block(A)
	if(isnull(why) && look_gameplay_state(A) != gameplay_before)
		why = "the first draw moved light, opacity, density or verbs"
	GLOB.type_look_lazy[A.type] = isnull(why)
	if(why)
		GLOB.type_look_lazy_why[A.type] = why

/// The rule that keeps `A`'s type from deriving nothing but a look, or null when it does.
/proc/look_lazy_block(atom/A)
	if(ismob(A))
		return "mob"
	var/flags = GLOB.type_derives_cache[A.type]
	if(isnull(flags))
		return "derive flags unknown"
	if(flags & TYPE_DERIVES_PENDING)
		return "derives: pending"
	if(flags & TYPE_DERIVES_SIDE)
		return "derives: side effects"
	if(flags & TYPE_DERIVES_DEPS)
		return "derives: values (deps)"
	if(A.periodic_cadence || A.periodic_interval)
		return "periodic work"
	if(LAZYLEN(A.open_tguis))
		return "open window"
	if(A.rx && (A.rx.refresh_hidden_verbs || A.rx.refresh_granted_verbs))
		return "hides or grants verbs"
	if(capability_data(A)?[/datum/cap_engine_state])
		return "capability watches or flashes"
	return null

/// Whether `A` derives nothing but a look: the type_look_default_empty() test, minus the look.
/proc/look_cosmetic_only(atom/A)
	return isnull(look_lazy_block(A))

/// Parked first draws that a real mark had touched before the park (look-only marks made during init); the boot log reads it.
GLOBAL_VAR_INIT(refresh_parked_marked, 0)

/// TRUE when everything pending on `D` that would do anything for it is presentation: its queued bits restricted to its live outputs are within DEP_DRAW.
/proc/refresh_pending_look_only(datum/D)
	var/pending = D.refresh_queued & ~(DEP_CREATED | DEP_PARKED)
	return !(pending & refresh_live_outputs(D) & ~DEP_DRAW)

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
		var/live = (D.refresh_queued & ~(DEP_CREATED | DEP_PARKED)) & refresh_live_outputs(D)
		if(!live)
			dead++
			continue
		if(live & DEP_DRAW)
			look++
		if(live & DEP_VALUES)
			values++
		if(live & (DEP_PUSH | DEP_LEGACY))
			effects++
		if(live & (DEP_UI | DEP_RUN))
			windows++
	return "[entries] entries ([datums] datums): look [look], values [values], effects [effects], ui/run [windows], nothing live [dead]"

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
	log_world("refresh queue by kind before the park: [refresh_kind_census(Q)]")
	var/list/kept = list()
	var/parked = 0
	var/marked_parked = 0
	for(var/datum/D as anything in Q)
		if(isnull(D) || !D.refresh_queued || D.refresh_queued == DEP_PARKED)
			continue // (a stale duplicate of an atom already parked leaves too)
		// What is pending is judged by kind, not by whether a real mark touched it: a lazy type's live outputs are its look alone, so a mark made
		// while the map was still initializing (a pipe joining its neighbours, a cable's network) is presentation too and waits for a viewer like
		// the creation mark does (doc/rewrite/proposals/demand_driven_refresh.md 2.2).
		if(isatom(D) && look_lazy_ok(D) && refresh_pending_look_only(D))
			if(!(D.refresh_queued & DEP_CREATED))
				marked_parked++
			D.refresh_queued = DEP_PARKED
			D.refresh_bits = 0
			parked++
			continue
		kept += D
	refresh_queue_replace(kept)
	GLOB.refresh_parked += parked
	GLOB.refresh_parked_marked += marked_parked
	GLOB.refresh_park_residual = refresh_park_residual_text(Q)
	log_world("refresh park: [parked] first draw(s) parked for a client to come near ([marked_parked] of them marked since creation, look only), [length(Q)] kept queued, [(REALTIMEOFDAY - start) * 100] ms")
	log_world("refresh queue by kind after the park: [refresh_kind_census(Q)]")
	log_world("refresh park residual (kept queued, by type and the rule that kept it): [GLOB.refresh_park_residual]")
	return parked

/// The park census of what stayed queued: the busiest types with the rule that excluded each ("not sampled" when no instance of the type was refreshed first).
GLOBAL_VAR_INIT(refresh_park_residual, "")

/// The `top` types with the most queued entries in `Q`, each with the rule that kept it out of the park, as one line. Totals by rule come first.
/proc/refresh_park_residual_text(list/Q, top = 25)
	var/list/by_type = list()
	var/list/by_rule = list()
	for(var/datum/D as anything in Q)
		if(isnull(D))
			continue
		var/why
		if(!isatom(D))
			why = "not an atom"
		else if(isnull(GLOB.type_look_lazy[D.type]))
			why = "type not sampled"
		else if(GLOB.type_look_lazy[D.type])
			why = "instance: periodic work or open window"
		else
			why = GLOB.type_look_lazy_why[D.type] || "verdict false"
		var/key = "[D.type] ([why])"
		by_type[key] = (by_type[key] || 0) + 1
		by_rule[why] = (by_rule[why] || 0) + 1
	var/text = "rules:"
	for(var/rule in by_rule)
		text += " [rule] x[by_rule[rule]],"
	text += " types:"
	for(var/n in 1 to top)
		var/best
		for(var/key in by_type)
			if(isnull(best) || by_type[key] > by_type[best])
				best = key
		if(isnull(best))
			break
		text += " [best] x[by_type[best]],"
		by_type -= best
	return text

// ---- draw on first view: the fresh atoms of a map load wait by type, not in the queue ----
//
// A type's look verdict (type_look_stamp, type_look_lazy) is learned from one sampled first draw. Before it is known, a map load used to queue every
// fresh atom for its first refresh (519 k at a full-map boot), and the settle walked them all to drop the 368 k of types whose default look is empty.
// Now the first fresh instance of a type with no verdict yet is queued as its sample, and every later one is held out of the queue: parked (DEP_PARKED,
// it owes its whole first refresh) in its type's bucket. refresh_settle_created() decides each bucket from the sample: an empty default look owes
// nothing; any other is queued again for its first refresh as before, where the park or the boot drain takes it. A real mark on a held atom queues it
// at once with what it owes (refresh_mark()), and its bucket entry is then skipped.

/// type -> the fresh atoms of a map load held for the type's verdict (boot_created_hold()). Null outside a load's settle window.
GLOBAL_LIST_EMPTY(boot_created_buckets)
/// type -> TRUE once a fresh instance of the type has been queued as its sample during a map load.
GLOBAL_LIST_EMPTY(boot_created_sampled)
/// Fresh atoms held by type, and how many of them the settle released without a draw (the bench reads both).
/// TRUE once the boot settle ran: a later map load (an expedition, a template) queues its fresh atoms as before, since no settle follows it.
GLOBAL_VAR_INIT(boot_created_settled, FALSE)
GLOBAL_VAR_INIT(boot_created_held, 0)
GLOBAL_VAR_INIT(boot_created_dropped, 0)

/// caps_init(), for a fresh `A` not yet queued: TRUE when it is held in its type's bucket instead of queued (made by the boot map load, a type with no
/// verdict, its sample already queued). FALSE queues it as before; the first such instance of a type is recorded as the sample.
/// Only an atom on the map (a turf, or anything with a turf under it) waits: a client's HUD (its plane masters and fullscreen overlays, which live
/// in nullspace) made while the server boots, for a player who connects early, is drawn at once. A held or parked screen object is never viewed
/// the way a turf's contents are, so it stayed undrawn and the player kept a grey screen. (`mapload` cannot tell them apart: INITIALIZE_IMMEDIATE
/// types, the HUD's among them, always initialize as a map load.)
/proc/boot_created_hold(atom/A)
	if(isnull(get_turf(A)))
		return FALSE
	look_verdicts_load() // the verdicts a previous boot of this world learned: a known type is neither held nor sampled
	if(GLOB.boot_created_settled || !materialization_host().frame_running() || ismob(A) || A.periodic_cadence || A.periodic_interval)
		return FALSE
	if(!isnull(GLOB.type_look_stamp[A.type]))
		// A known verdict (a previous boot of this world): a lazy type's fresh atom is parked at once when the boot leaves first draws to the clients,
		// as the park would make of it, without a queue entry; any other is queued as before.
		if(GLOB.type_look_lazy[A.type] && look_lazy_ok(A) && boot_drain_deferred())
			A.refresh_queued = DEP_PARKED
			GLOB.refresh_parked++
			return TRUE
		return FALSE
	if(!GLOB.boot_created_sampled[A.type])
		GLOB.boot_created_sampled[A.type] = TRUE
		return FALSE
	var/list/bucket = GLOB.boot_created_buckets[A.type]
	if(!bucket)
		bucket = list()
		GLOB.boot_created_buckets[A.type] = bucket
	bucket += A
	A.refresh_queued = DEP_PARKED
	GLOB.boot_created_held++
	return TRUE

/// refresh_forget(): a held atom is destroyed before the settle: it leaves its bucket (it was appended last, so the search from the end is short).
/proc/boot_created_forget(datum/D)
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
		if(empty)
			. += length(bucket) // released in one step: a parked atom of an empty default look owes nothing (interest_audit_atom(), interest_draw_now())
			continue
		if(GLOB.type_look_lazy[type] && boot_drain_deferred())
			continue // a lazy type's held atoms are parked already, which is what the park would make of them: they draw when a client comes near
		for(var/atom/A as anything in bucket)
			if(QDELETED(A) || A.refresh_queued != DEP_PARKED)
				continue // deleted, or a real mark queued it already with what it owed
			A.refresh_queued = 0
			refresh_mark(A, DEP_ALL)
			A.refresh_queued |= DEP_CREATED
	GLOB.boot_created_dropped += .

// ---- the look verdicts across boots ----
//
// A type's look verdicts (type_look_stamp: its default look is empty; type_look_lazy: its first draw is a picture only) are facts of the compiled world
// and the map. The boot that learns them by sampling writes them to data/look_verdicts.json keyed by that world (look_verdicts_key()); the next boot of
// the same world reads them before the map loads, so a fresh atom of a known type is never queued or sampled and the boot settle has almost nothing
// to do. A world compiled or mapped differently has another key and samples again. dq_look_verdict_cache_agrees proves the cache equals the sampling.
// Deriving the verdicts from the declarations at build time is the analyzer's follow-up (doc/rewrite/proposals/init_plan.md).

#define LOOK_VERDICTS_FILE "data/look_verdicts.json"

/// The identity the cache is valid for: the compiler, the map and a hash of every compiled .dmb and .rsc in the working directory.
/proc/look_verdicts_key()
	var/static/key
	if(!isnull(key))
		return key
	var/list/parts = list("[DM_VERSION].[DM_BUILD]", "[world.maxx]x[world.maxy]x[world.maxz]") // the maps are compiled into the .dmb and .rsc hashed below
	for(var/file in sortList(flist("./")))
		var/extension = lowertext(copytext(file, -4))
		if((extension == ".dmb" || extension == ".rsc") && !findtext(file, ".dyn.rsc"))
			parts += "[file]=[rustg_hash_file(RUSTG_HASH_XXH64, file)]"
	key = jointext(parts, "|")
	return key

/// Verdicts loaded from the cache this boot (the bench and the test read it).
GLOBAL_VAR_INIT(look_verdicts_loaded, 0)

/// Reads the cached verdicts into the verdict tables when the cache was written by this world. Once per boot, before the map's atoms initialize.
/proc/look_verdicts_load()
	var/static/done = FALSE
	if(done)
		return
	done = TRUE
	if(!fexists(LOOK_VERDICTS_FILE))
		return
	if(!look_verdicts_apply(json_decode(file2text(LOOK_VERDICTS_FILE))))
		log_world("LOOK VERDICTS: the cache was written by another world; sampling at boot")
		return
	log_world("LOOK VERDICTS: [GLOB.look_verdicts_loaded] type verdict(s) read from the cache")

/// Puts the verdicts of a cache document into the verdict tables when the document was written by this world (its key). FALSE, reading nothing,
/// for a document of another world: its verdicts would draw this world's atoms wrong.
/proc/look_verdicts_apply(list/data)
	if(!islist(data) || data["key"] != look_verdicts_key())
		return FALSE
	var/list/stamp = data["stamp"]
	var/list/lazy = data["lazy"]
	for(var/name in stamp)
		var/path = text2path(name)
		if(path && isnull(GLOB.type_look_stamp[path]))
			GLOB.type_look_stamp[path] = !!stamp[name]
			GLOB.look_verdicts_loaded++
	for(var/name in lazy)
		var/path = text2path(name)
		if(path && isnull(GLOB.type_look_lazy[path]))
			GLOB.type_look_lazy[path] = !!lazy[name]
	return TRUE

/// Writes every verdict known now (the boot settle has sampled what was new), for the next boot of this world.
/proc/look_verdicts_save()
	var/list/stamp = list()
	var/list/lazy = list()
	for(var/path in GLOB.type_look_stamp)
		stamp["[path]"] = GLOB.type_look_stamp[path] ? 1 : 0
	for(var/path in GLOB.type_look_lazy)
		lazy["[path]"] = GLOB.type_look_lazy[path] ? 1 : 0
	fdel(LOOK_VERDICTS_FILE)
	text2file(json_encode(list("key" = look_verdicts_key(), "stamp" = stamp, "lazy" = lazy)), LOOK_VERDICTS_FILE)
	log_world("LOOK VERDICTS: [length(stamp)] type verdict(s) written for the next boot")
