// Sparse declared links (doc/rewrite/final_api.html, section 6 "References and lifecycle"; doc/rewrite/framework_gaps.md KR2, KR4).
//
// links(LINK_END(/mob/living, LK_BUCKLED_TO), LINK_END(/atom/movable, LK_BUCKLED_MOBS), sparse = TRUE, b_many = TRUE, ...) declares a pair whose two ends
// are not vars. A base type cannot carry a var for every relation it might take part in (base_vars: /mob, /mob/living, /atom/movable), so a sparse end
// lives in the holder's engine record, `rx.link_ends[key]`: the one linked datum, or a list of them for a `*_many` end. Nothing on the holder's type
// declares it; the accessors of the type read it with link_get() / link_list() and the verbs below write both ends in one step:
//
//   link_make(holder, key, other)       link holder.key to other (both ends written, the far end's old link broken when it takes only one)
//   link_break(holder, key, other)      break one link (other = null: every link of that end)
//   link_get(holder, key)               the one datum linked, or null
//   link_list(holder, key)              a fresh list of the datums linked, never null
//
// What a sparse pair may say beyond what a var-backed pair says (every argument is of links() / entry_link()):
//
//   holds_while = PROC_REF(x)           a condition, `x(other)` called on the holder of the pair's A end: it returns TRUE while the link may stand. A link
//                                       made while it is false is refused; one that turns false breaks with RELATION_BROKEN and the declared on_unlink
//                                       hooks. It is not polled: it is re-evaluated one tick after a move notice of either end (a rider carried along
//                                       with its seat, a pulled thing following its puller, settles first).
//   a_contributes = list(STAT_X, value, ...)   (and b_contributes) stat holds the link puts on that end's holder while it stands. The other end is the
//                                       hold's source, so breaking the link, or either end going, releases them.
//   conflict = REFUSE | REPLACE         what linking does to an end that takes one link and already has one: REPLACE (the default) breaks the old link
//                                       (its hooks run), REFUSE leaves it and the new link is not made.
//
// a_on_unlink / b_on_unlink (and a_on_other_deleted / b_on_other_deleted) mean what they mean for a var-backed pair: the hook is `holder.x(other)`, not told
// when the holder is the one being destroyed; OTHER_DELETE_ME deletes the holder when the other end is deleted.

/// Registry of the sparse pairs by end key: key -> list(entry, "a" or "b"). Built from the link declarations the first time it is asked after a new one
/// was registered (they are registered while the type tables build, which can come during global init, so this never runs from there).
GLOBAL_LIST_EMPTY(link_sparse_by_key)
GLOBAL_VAR_INIT(link_sparse_seen, 0)

/// The sparse-pair index row of end `key` (list(entry, end)), or null when no declared pair has that end.
/proc/link_end_row(key)
	var/list/decls = link_decls_cache()
	if(length(decls) != GLOB.link_sparse_seen)
		GLOB.link_sparse_seen = length(decls)
		GLOB.link_sparse_by_key.Cut()
		for(var/sig in decls)
			var/datum/entry/E = decls[sig]
			if(!E.args["sparse"])
				continue
			GLOB.link_sparse_by_key[E.args["a_var"]] = list(E, "a")
			GLOB.link_sparse_by_key[E.args["b_var"]] = list(E, "b")
	return GLOB.link_sparse_by_key[key]

/// The datum linked at holder's end `key` (a single end), or null. A many end answers its list: use link_list().
/proc/link_get(datum/holder, key)
	return holder?.rx?.link_ends?[key]

/// A fresh list of every datum linked at holder's end `key`; empty when none.
/proc/link_list(datum/holder, key)
	var/value = holder?.rx?.link_ends?[key]
	if(islist(value))
		var/list/members = value
		return members.Copy()
	return isnull(value) ? list() : list(value)

/// Is `other` linked at holder's end `key`?
/proc/link_has(datum/holder, key, datum/other)
	var/value = holder?.rx?.link_ends?[key]
	if(islist(value))
		return other in value
	return !isnull(other) && value == other

/// Data the link at holder's end `key` carries (read by the end's on_unlink hook, which runs before it is cleared).
/proc/link_data_set(datum/holder, key, name, value)
	var/datum/rx_state/state = rx_of(holder)
	var/list/data = state.link_data?[key]
	if(!data)
		data = list()
		LAZYSET(state.link_data, key, data)
	data[name] = value

/proc/link_data_get(datum/holder, key, name)
	var/list/data = holder?.rx?.link_data?[key]
	return data?[name]

/// Writes one end.
/proc/link_store(datum/holder, key, datum/other, many)
	var/datum/rx_state/state = rx_of(holder)
	if(!many)
		LAZYSET(state.link_ends, key, other)
		return
	var/list/members = state.link_ends?[key]
	if(!islist(members))
		members = list()
		LAZYSET(state.link_ends, key, members)
	members += other

/// Clears one end of `other`; TRUE when it was there.
/proc/link_unstore(datum/holder, key, datum/other, many)
	var/datum/rx_state/state = holder?.rx
	if(!state?.link_ends)
		return FALSE
	if(!many)
		if(state.link_ends[key] != other)
			return FALSE
		state.link_ends -= key
		UNSETEMPTY(state.link_ends)
		return TRUE
	var/list/members = state.link_ends[key]
	if(!islist(members) || !(other in members))
		return FALSE
	members -= other
	if(!length(members))
		state.link_ends -= key
		UNSETEMPTY(state.link_ends)
	return TRUE

/// The holder at end `end` is `a`, the other `b`: do the declared condition and the types agree?
/proc/link_holds(datum/entry/E, datum/a, datum/b)
	var/condition = E.args["holds_while"]
	if(!condition)
		return TRUE
	return !!call(a, condition)(b)

/// Is `other` at distance `range` or less of `src`, on the same level? What a range condition reads.
/atom/proc/link_in_range(atom/other, range)
	var/turf/here = get_turf(src)
	var/turf/there = get_turf(other)
	return here && there && here.z == there.z && get_dist(here, there) <= range

/// Links holder's end `key` to `other` (the far end of the pair). TRUE when the link stands afterwards (also when it already did); FALSE when it was
/// refused: a type that is not the end's, an end being destroyed, a REFUSE conflict, a holds_while that is false now.
/proc/link_make(datum/holder, key, datum/other)
	var/list/row = link_end_row(key)
	if(!row)
		declare_report("link_make([holder?.type], \"[key]\"): no declared pair has that end")
		return FALSE
	var/datum/entry/E = row[1]
	var/end = row[2]
	var/far = end == "a" ? "b" : "a"
	if(!istype(holder, E.args["[end]_type"]) || !istype(other, E.args["[far]_type"]))
		declare_report("link_make([holder?.type], \"[key]\", [other?.type]): the ends are [E.args["[end]_type"]] and [E.args["[far]_type"]]")
		return FALSE
	if(holder == other || QDELETED(holder) || QDELETED(other))
		return FALSE
	if(!own_guard(holder, other, "a [key] link")) // the one teardown guard (guard.dm)
		return FALSE
	if(link_has(holder, key, other))
		return TRUE
	var/far_key = E.args["[far]_var"]
	var/datum/end_a = end == "a" ? holder : other
	var/datum/end_b = end == "a" ? other : holder
	if(!link_holds(E, end_a, end_b))
		return FALSE
	var/datum/old_here = E.args["[end]_many"] ? null : link_get(holder, key)
	var/datum/old_there = E.args["[far]_many"] ? null : link_get(other, far_key)
	if((old_here || old_there) && E.args["conflict"] == REFUSE)
		return FALSE
	if(old_here)
		link_unmake(E, end, holder, old_here, null, RELATION_REPLACED)
	if(old_there)
		link_unmake(E, far, other, old_there, null, RELATION_REPLACED)
	link_store(holder, key, other, E.args["[end]_many"])
	link_store(other, far_key, holder, E.args["[far]_many"])
	link_holds_place(E, end, holder, other)
	link_holds_place(E, far, other, holder)
	if(E.args["holds_while"])
		link_watch_start(E, end_a, end_b)
	return TRUE

/// Breaks the link of holder's end `key` to `other`, or every link of that end when `other` is null. TRUE when something was broken.
/proc/link_break(datum/holder, key, datum/other = null)
	var/list/row = link_end_row(key)
	if(!row)
		return FALSE
	var/datum/entry/E = row[1]
	if(isnull(other))
		. = FALSE
		for(var/datum/each as anything in link_list(holder, key))
			. = link_unmake(E, row[2], holder, each, null, RELATION_UNLINKED) || .
		return
	return link_unmake(E, row[2], holder, other, null, RELATION_UNLINKED)

/// The link of `holder` (at end `end` of E's pair) to `other` goes: both ends cleared, the watch stopped, the holds released, then the declared hooks (A
/// end's first), then the delete-the-holder policy of the end whose far end is `deleting`. Nothing holds it already: FALSE.
/proc/link_unmake(datum/entry/E, end, datum/holder, datum/other, datum/deleting, reason)
	var/far = end == "a" ? "b" : "a"
	var/key = E.args["[end]_var"]
	var/far_key = E.args["[far]_var"]
	var/removed = link_unstore(holder, key, other, E.args["[end]_many"])
	removed = link_unstore(other, far_key, holder, E.args["[far]_many"]) || removed
	if(!removed)
		return FALSE
	var/datum/end_a = end == "a" ? holder : other
	var/datum/end_b = end == "a" ? other : holder
	if(E.args["holds_while"])
		link_watch_stop(E, end_a, end_b)
	link_holds_release(E, end, holder, other, deleting)
	link_holds_release(E, far, other, holder, deleting)
	for(var/side in list("a", "b"))
		var/datum/mine = side == end ? holder : other
		var/datum/theirs = side == end ? other : holder
		var/hook = E.args["[side]_on_unlink"]
		if(hook && mine != deleting && !QDELETED(mine))
			call(mine, hook)(theirs)
	link_data_clear(holder, key, far_key, other)
	if(deleting)
		var/datum/survivor = deleting == holder ? other : holder
		var/survivor_end = deleting == holder ? far : end
		if(E.args["[survivor_end]_on_other_deleted"] == OTHER_DELETE_ME && !QDELETED(survivor))
			ended_with(survivor, deleting)
	return TRUE

/// The destroy transaction's links step: every link `D` is an end of breaks, the holders it leaves told (code/datums/lifecycle/links.dm).
/proc/link_teardown(datum/D)
	var/list/ends = D.rx?.link_ends
	if(!length(ends))
		return
	for(var/key in ends.Copy())
		var/list/row = link_end_row(key)
		if(!row)
			continue
		for(var/datum/other as anything in link_list(D, key))
			link_unmake(row[1], row[2], D, other, D, RELATION_DESTROYING)

// ---- contributes ----

/// The stat holds the link puts on `holder` (the holder of end `end`), the other end the source of each.
/proc/link_holds_place(datum/entry/E, end, datum/holder, datum/other)
	var/list/stats = E.args["[end]_contributes"]
	for(var/i in 1 to length(stats) step 2)
		var/datum/stat_def/def = stat_def_of(stats[i])
		if(def && stat_declared_on(holder.type, def))
			hold(holder, stats[i], stats[i + 1], other)

/// Releases them. A holder being destroyed releases with the rest of its stats.
/proc/link_holds_release(datum/entry/E, end, datum/holder, datum/other, datum/deleting)
	if(holder == deleting || QDELETED(holder))
		return
	var/list/stats = E.args["[end]_contributes"]
	for(var/i in 1 to length(stats) step 2)
		release(holder, stats[i], other)

// ---- holds_while ----

/datum/rx_state
	/// Data a link carries for one of its ends (the orbiter's saved transform): end key -> list(name = value), gone with the link.
	var/list/link_data
	/// The holds_while links this datum is an end of, as list(entry, A end, B end) rows (both ends keep the same row).
	var/list/link_watches
	/// Sparse link ends (links(sparse = TRUE)): end key -> the one linked datum, or a list of them (code/engine/declare/link_state.dm).
	var/list/link_ends

/proc/link_watch_start(datum/entry/E, datum/a, datum/b)
	var/list/row = list(E, a, b)
	for(var/datum/end in list(a, b))
		var/datum/rx_state/state = rx_of(end)
		if(!state.link_watches)
			state.link_watches = list()
			observe(end, /datum/notice/moved, GLOB.link_watcher, then(TYPE_PROC_REF(/datum/link_watcher, ends_moved)))
		state.link_watches += list(row)

/proc/link_watch_stop(datum/entry/E, datum/a, datum/b)
	for(var/list/row as anything in a.rx?.link_watches?.Copy())
		if(row[1] != E || row[3] != b)
			continue
		for(var/datum/end in list(a, b))
			var/datum/rx_state/state = end.rx
			if(!state?.link_watches)
				continue
			state.link_watches.Remove(list(row))
			if(!length(state.link_watches))
				state.link_watches = null
				unobserve(end, /datum/notice/moved, GLOB.link_watcher)

/// The one listener of the move notices of every end of a holds_while link (observe(), as orbiting does): `D` moved, so each holds_while link it is an end of
/// is looked at again once the move, and what follows it (a rider carried with its seat, a pulled thing following), has settled.
/datum/link_watcher

GLOBAL_DATUM_INIT(link_watcher, /datum/link_watcher, new)

/datum/link_watcher/proc/ends_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	link_ends_moved(A.target)

/proc/link_ends_moved(datum/D)
	after_unique(D, 0.1 SECONDS, TYPE_PROC_REF(/datum, link_recheck))

/// The deferred look of link_ends_moved(): every holds_while link this datum is an end of, once.
/datum/proc/link_recheck()
	for(var/list/row as anything in rx?.link_watches?.Copy())
		var/datum/entry/entry = row[1]
		var/datum/end_a = row[2]
		var/datum/end_b = row[3]
		if(QDELETED(end_a) || QDELETED(end_b) || link_holds(entry, end_a, end_b))
			continue
		log_world("LINK: [entry.args["a_var"]] [end_a.type] -> [end_b.type] no longer holds: broken")
		link_unmake(entry, "a", end_a, end_b, null, RELATION_BROKEN)

/// A link's data goes with it (a many end keeps the data of its other links: it is kept per end key, so a many end carries none).
/proc/link_data_clear(datum/holder, key, far_key, datum/other)
	var/datum/rx_state/state = holder.rx
	if(state?.link_data)
		state.link_data -= key
		UNSETEMPTY(state.link_data)
	state = other.rx
	if(state?.link_data)
		state.link_data -= far_key
		UNSETEMPTY(state.link_data)
