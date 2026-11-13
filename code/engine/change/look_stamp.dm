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
	if(LAZYLEN(A.open_tguis))
		return FALSE
	if(A.rx && (!isnull(A.rx.look_key) || A.rx.refresh_hidden_verbs || A.rx.refresh_granted_verbs))
		return FALSE
	if(capability_data(A)?[/datum/cap_engine_state])
		return FALSE // it watches something or flashes: not a look the mapped appearance stands for
	return TRUE

/// TRUE when a fresh `D` of a stamped type needs no first refresh (its type's verdict is in and its default look is empty).
/proc/type_look_stamped(datum/D)
	if(!GLOB.type_look_stamp[D.type] || LAZYLEN(D.open_tguis) || !look_verdict_fits(D))
		return FALSE
	var/flags = GLOB.type_derives_cache[D.type]
	return !isnull(flags) && !(flags & TYPE_DERIVES_PENDING)

/// Records the stamp from a fresh instance's first refresh, once per type.
/proc/type_look_stamp_record(datum/D)
	if(isnull(GLOB.type_look_stamp[D.type]))
		GLOB.type_look_stamp[D.type] = type_look_default_empty(D)
		look_verdicts_learned(D.type)

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
		if(!fresh_sample && (!isatom(D) || (!isnull(GLOB.type_look_lazy[D.type]) && look_lazy_reachable(D))))
			continue // (a known lazy verdict spares only an atom a client can come near: any other is drawn now)
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
	var/unperceived = 0
	for(var/datum/D as anything in Q)
		if(isnull(D) || !D.refresh_queued)
			continue
		if(D.refresh_queued & DEP_CREATED && type_look_stamped(D))
			D.refresh_queued = 0
			D.refresh_bits = 0
			skipped++
			continue
		// Nothing is drawn that no viewer could perceive (draw_perceivable(), interest.dm): an atom of a type whose first draw is only a picture, covered
		// by its floor, contained or abstractly invisible, waits parked, owing everything, until a reveal marks it (a tile lifted, a move out, a write).
		if(isatom(D) && GLOB.type_look_lazy[D.type] && look_lazy_ok(D) && !draw_perceivable(D))
			var/atom/held = D
			if(isturf(held.loc) && held.invisibility < INVISIBILITY_ABSTRACT)
				stack_trace("refresh settle: [held.type] at [held.x],[held.y],[held.z] is visible today (invisibility [held.invisibility], on its turf) but was taken for unperceivable")
			D.refresh_queued = DEP_PARKED
			D.refresh_bits = 0
			GLOB.interest_unperceivable_skipped++
			unperceived++
			continue
		kept += D
	refresh_queue_replace(kept)
	var/walked_at = REALTIMEOFDAY
	skipped += boot_created_release() // the atoms held by type while the map loaded: an empty default look owes nothing, the rest are queued now
	look_verdicts_save()
	log_world("refresh settle: [unperceived] first draw(s) of atoms no viewer could perceive left parked")
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
	look_verdicts_learned(A.type)

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
		if(live & DEP_UI)
			windows++
	return "[entries] entries ([datums] datums): look [look], values [values], effects [effects], ui [windows], nothing live [dead]"

/// Whether a client can come near `A`: only an atom standing somewhere interest can reach is ever drawn on a viewer's approach (interest_enter() walks the
/// contents of chunks). An area has no place and an atom in nullspace has none either, so a parked draw of theirs would never be asked for: they are never
/// lazy, whatever a sampled or cached verdict says (a verdict cache written by an older build marks areas lazy).
/proc/look_lazy_reachable(atom/A)
	return !isarea(A) && !isnull(get_turf(A))

/// Whether a fresh queued `A` may be parked: its type's verdict is lazy and this instance has nothing the verdict did not see.
/proc/look_lazy_ok(atom/A)
	if(!look_lazy_reachable(A) || !GLOB.type_look_lazy[A.type] || LAZYLEN(A.open_tguis) || !look_verdict_fits(A))
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
	if(GLOB.boot_created_settled || ismob(A) || isnull(get_turf(A)) || !materialization_host().frame_running())
		return FALSE // the cheap tests first: this runs for every atom created at boot
	look_verdicts_load() // the verdicts a previous boot of this world learned: a known type is neither held nor sampled
	if(!isnull(GLOB.type_look_stamp[A.type]) && look_verdict_fits(A))
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
/// The cache's format version: it is part of the key and of the document, so a change to what a verdict means (or how it is stored) discards every older file.
#define LOOK_VERDICTS_VERSION 2
/// How long after a verdict is learned (past the boot settle) the cache is written again; verdicts learned meanwhile share the one write.
#define LOOK_VERDICTS_SAVE_DELAY (30 SECONDS)

/// The identity the cache is valid for: the format version, the compiler, the map and a hash of every compiled .dmb and .rsc in the working directory.
/// A map loaded at runtime (expedition, submaps) is not in it; look_verdict_fits() judges each instance against the type's default instead.
/proc/look_verdicts_key()
	var/static/key
	if(!isnull(key))
		return key
	var/list/parts = list("v[LOOK_VERDICTS_VERSION]", "[DM_VERSION].[DM_BUILD]", "[world.maxx]x[world.maxy]x[world.maxz]") // the maps are compiled into the .dmb and .rsc hashed below
	for(var/file in sortList(flist("./")))
		var/extension = lowertext(copytext(file, -4))
		if((extension == ".dmb" || extension == ".rsc") && !findtext(file, ".dyn.rsc"))
			parts += "[file]=[rustg_hash_file(RUSTG_HASH_XXH64, file)]"
	key = jointext(parts, "|")
	return key

/// Verdicts loaded from the cache this boot (the bench and the test read it).
GLOBAL_VAR_INIT(look_verdicts_loaded, 0)
/// Type path -> TRUE for a type whose verdict came from the cache rather than from a sample of this boot. Only these are judged per instance
/// (look_verdict_fits()): a sampled verdict has its instance in the world, a cached one has none behind it.
GLOBAL_LIST_EMPTY(look_verdict_from_file)
/// Instances a cached verdict was refused for (an edited look var), for the boot log.
GLOBAL_VAR_INIT(look_verdict_unfit, 0)
/// Verdict count (stamp plus lazy) at the last write of the cache; the debounced save writes only when the tables have grown past it. -1: not written yet.
GLOBAL_VAR_INIT(look_verdicts_saved, -1)
/// TRUE while the debounced save is waiting.
GLOBAL_VAR_INIT(look_verdicts_save_pending, FALSE)
/// Type paths whose verdict was learned since the cache was last written (a full save or a journal append): what the next flush appends.
GLOBAL_LIST_EMPTY(look_verdicts_unwritten)
/// Journal appends made this boot, the verdicts they held, and the ms the last one took (the trace line and the tests read them).
GLOBAL_VAR_INIT(look_verdicts_appends, 0)
GLOBAL_VAR_INIT(look_verdicts_appended, 0)
GLOBAL_VAR_INIT(look_verdicts_last_flush_ms, 0)

/// Whether a cached verdict may be applied to `D`. A cached verdict says what the type's default look is; an instance whose look vars were edited (a
/// map var edit, a runtime-loaded map, a varedit) is not that default, so it is never spared by it and is handled as if no verdict were known.
/// A verdict this boot sampled is not judged here (cheap exit).
/proc/look_verdict_fits(datum/D)
	if(!GLOB.look_verdict_from_file[D.type] || !isatom(D))
		return TRUE
	var/atom/A = D
	if(A.icon_state != initial(A.icon_state) || A.icon != initial(A.icon) || A.color != initial(A.color) || A.alpha != initial(A.alpha) \
		|| A.dir != initial(A.dir) || A.layer != initial(A.layer) || A.plane != initial(A.plane) || A.invisibility != initial(A.invisibility) \
		|| A.pixel_x != initial(A.pixel_x) || A.pixel_y != initial(A.pixel_y) || A.opacity != initial(A.opacity) || A.density != initial(A.density) \
		|| A.blend_mode != initial(A.blend_mode) || A.mouse_opacity != initial(A.mouse_opacity) || A.name != initial(A.name))
		GLOB.look_verdict_unfit++
		return FALSE
	return TRUE

/// The document of a cache file: a list, or null when there is no file, it is not valid JSON (a write cut short, a hand edit) or it is not an object.
/// A bad file is logged and left for the next save to replace.
/proc/look_verdicts_read(file = LOOK_VERDICTS_FILE)
	if(!fexists(file))
		return null
	var/text = file2text(file)
	if(!istext(text) || !rustg_json_is_valid(text))
		log_world("LOOK VERDICTS: [file] is not valid JSON ([length(text)] bytes); ignored, sampling at boot")
		return null
	var/list/doc = json_decode(text)
	if(!islist(doc))
		log_world("LOOK VERDICTS: [file] is not an object; ignored, sampling at boot")
		return null
	return doc

/// Reads the cached verdicts into the verdict tables when the cache was written by this world. Once per boot, before the map's atoms initialize.
/proc/look_verdicts_load()
	var/static/done = FALSE
	if(done)
		return
	done = TRUE
	var/list/doc = look_verdicts_read()
	if(isnull(doc))
		return
	if(!look_verdicts_apply(doc))
		log_world("LOOK VERDICTS: the cache was written by another world or format; sampling at boot")
		return
	var/journaled = look_verdicts_read_journal()
	log_world("LOOK VERDICTS: [GLOB.look_verdicts_loaded] type verdict(s) read from the cache ([journaled] of them from its journal)")

/// Applies the journal of verdicts appended after the file was written (the cache file's name and ".journal": one document per line, only the types learned
/// since the last full save; the next full save folds it in and deletes it): every line that is a whole document of this world is read,
/// a line cut short (a write that did not finish) is skipped. Returns the verdicts the journal added.
/proc/look_verdicts_read_journal(file = "[LOOK_VERDICTS_FILE].journal")
	if(!fexists(file))
		return 0
	var/before = GLOB.look_verdicts_loaded
	var/text = file2text(file)
	if(!istext(text))
		return 0
	for(var/line in splittext(text, "\n"))
		if(!length(line) || !findtext(line, "{", 1, 2) || !rustg_json_is_valid(line))
			continue
		var/list/doc = json_decode(line)
		if(islist(doc))
			look_verdicts_apply(doc)
	return GLOB.look_verdicts_loaded - before

/// Puts the verdicts of a cache document into the verdict tables when the document was written by this world and format (its version and key). FALSE,
/// reading nothing, for any other document: its verdicts would draw this world's atoms wrong.
/proc/look_verdicts_apply(list/data)
	if(!islist(data) || data["version"] != LOOK_VERDICTS_VERSION || data["key"] != look_verdicts_key())
		return FALSE
	var/list/stamp = data["stamp"]
	var/list/lazy = data["lazy"]
	if(!islist(stamp) || !islist(lazy))
		return FALSE
	for(var/name in stamp)
		var/path = text2path(name)
		if(path && isnull(GLOB.type_look_stamp[path]))
			GLOB.type_look_stamp[path] = !!stamp[name]
			GLOB.look_verdict_from_file[path] = TRUE
			GLOB.look_verdicts_loaded++
	for(var/name in lazy)
		var/path = text2path(name)
		if(path && isnull(GLOB.type_look_lazy[path]))
			GLOB.type_look_lazy[path] = !!lazy[name]
			GLOB.look_verdict_from_file[path] = TRUE
	return TRUE

/// Writes every verdict known now, for the next boot of this world. The document goes to a temporary file first and is read back before it replaces the
/// cache, so a write cut short never leaves a half file where the cache was. Returns whether the cache was replaced.
/proc/look_verdicts_save(file = LOOK_VERDICTS_FILE)
	var/list/stamp = list()
	var/list/lazy = list()
	for(var/path in GLOB.type_look_stamp)
		stamp["[path]"] = GLOB.type_look_stamp[path] ? 1 : 0
	for(var/path in GLOB.type_look_lazy)
		lazy["[path]"] = GLOB.type_look_lazy[path] ? 1 : 0
	var/temp = "[file].tmp"
	fdel(temp)
	var/document = json_encode(list("version" = LOOK_VERDICTS_VERSION, "key" = look_verdicts_key(), "stamp" = stamp, "lazy" = lazy))
	text2file(document, temp)
	// Read back and compared with what was written, then checked as JSON: a write cut short fails either test. It is not decoded again (a second
	// json_decode of the whole document was most of this proc's 60 ms, a hitch in the tick that wrote it).
	var/written = file2text(temp)
	// text2file() ends the line, so the file is the document and a newline.
	if(length(written) < length(document) || copytext(written, 1, length(document) + 1) != document || !rustg_json_is_valid(written))
		log_world("LOOK VERDICTS: the temporary cache [temp] did not write back; the cache [file] is left as it was")
		fdel(temp)
		return FALSE
	fcopy(temp, file) // a copy of a file already known good; BYOND has no rename
	fdel(temp)
	fdel("[file].journal") // what it held is in the file now
	GLOB.look_verdicts_unwritten.Cut()
	GLOB.look_verdicts_saved = length(GLOB.type_look_stamp) + length(GLOB.type_look_lazy)
	log_world("LOOK VERDICTS: [length(stamp)] type verdict(s) written for the next boot ([GLOB.look_verdict_unfit] instance(s) refused a cached verdict so far)")
	return TRUE

/// A verdict was just learned (type_look_stamp_record(), look_lazy_record()) for `path`. Once the boot settle has written the cache, new verdicts are
/// appended by one write a little later, so a type first made mid-round (an expedition map, a spawned item) is kept for the next boot too.
/proc/look_verdicts_learned(path)
	if(GLOB.look_verdicts_saved < 0)
		return
	GLOB.look_verdicts_unwritten |= path
	if(GLOB.look_verdicts_save_pending)
		return
	GLOB.look_verdicts_save_pending = TRUE
	after(null, LOOK_VERDICTS_SAVE_DELAY, GLOBAL_PROC_REF(look_verdicts_flush), clock = CLOCK_WORLD)

/// The debounced save: appends the verdicts learned since the last write to the journal, one line holding only them. What it costs follows what was learned (a
/// few types), not what is known (thousands): rewriting the whole cache here was a 57-64 ms call in a live tick.
/proc/look_verdicts_flush(file = LOOK_VERDICTS_FILE)
	GLOB.look_verdicts_save_pending = FALSE
	var/list/paths = GLOB.look_verdicts_unwritten
	if(!length(paths))
		return 0
	var/started = TICK_USAGE_REAL
	var/list/stamp = list()
	var/list/lazy = list()
	for(var/path in paths)
		if(!isnull(GLOB.type_look_stamp[path]))
			stamp["[path]"] = GLOB.type_look_stamp[path] ? 1 : 0
		if(!isnull(GLOB.type_look_lazy[path]))
			lazy["[path]"] = GLOB.type_look_lazy[path] ? 1 : 0
	var/count = length(paths)
	paths.Cut()
	var/line = json_encode(list("version" = LOOK_VERDICTS_VERSION, "key" = look_verdicts_key(), "stamp" = stamp, "lazy" = lazy))
	rustg_file_append("[line]\n", "[file].journal")
	GLOB.look_verdicts_appends++
	GLOB.look_verdicts_appended += count
	GLOB.look_verdicts_saved = length(GLOB.type_look_stamp) + length(GLOB.type_look_lazy)
	GLOB.look_verdicts_last_flush_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	log_world("LOOK VERDICTS: [count] new type verdict(s) appended to the journal in [round(GLOB.look_verdicts_last_flush_ms, 0.01)] ms ([GLOB.look_verdicts_appends] append(s) this boot)")
	return count
