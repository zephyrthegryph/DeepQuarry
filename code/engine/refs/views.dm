// Light relation edges: REF views (doc/rewrite/ownership.md §4.1).
//
// A REF var holds a direct reference (reads are free). The target keeps a lazy reverse index,
// `om_refs_in`: the source's key (own_key()) -> the var name (or a list of var names) naming it. The
// index is weak (keys, not references), so source and target never form a reference cycle. When either end
// dies the framework clears its side; nothing is kept by hand.
//
// Targets that never die need no index: registry singletons (REGISTRY_TYPE) and areas. Turfs
// are indexed per z-level (ChangeTurf resets a turf's vars), and rel_drop_z() clears them when
// the z-level is released.

/// Reverse index: source key (own_key()) -> var name, or a list of var names.
/datum/var/tmp/list/om_refs_in
/// Watching sources (rel_one/rel_many(watch = ...)): source key (own_key()) -> how many watched views of
/// that source name us. state_changed() on this datum marks each of them changed.
/datum/var/tmp/list/rel_watchers

/// z (text) -> turf key (own_key()) -> that turf's reverse index (as om_refs_in). A turf keeps no index of
/// its own: ChangeTurf() resets its vars, while its ref (its position) stays.
GLOBAL_LIST_EMPTY(rel_turf_index)
/// Handle id (text) -> flat list, stride 2: source key (own_key()), var name. Edges to an entity that
/// collapsed into latent data, re-linked when it re-materializes into the same handle slot.
GLOBAL_LIST_EMPTY(rel_dormant)

/// An index grows past this many sources before it prunes entries whose source was freed without
/// qdel() (a transient datum or event payload: its views never ran rel_teardown()).
#define REL_INDEX_PRUNE_AT 48

/// TRUE when references to `target` need tracking.
/proc/rel_tracked(datum/target)
	if(!isdatum(target) || isarea(target))
		return FALSE
	return isturf(target) || !is_registered(target)

/// `target`'s reverse index (source key (own_key()) -> var name or list of names), made when `create`.
/proc/_rel_index_of(datum/target, create = FALSE)
	if(isturf(target))
		var/turf/where = target
		var/zkey = "[where.z]"
		var/list/by_turf = GLOB.rel_turf_index[zkey]
		if(!by_turf)
			if(!create)
				return null
			by_turf = alist() // a z-level holds tens of thousands of turf keys: see below
			GLOB.rel_turf_index[zkey] = by_turf
		var/tkey = OWN_KEY(where)
		var/list/index = by_turf[tkey]
		if(!index && create)
			index = alist()
			by_turf[tkey] = index
		return index
	var/list/index = target.om_refs_in
	if(!index && create)
		// An alist, like every ref-keyed index here: inserting a new key into a plain assoc list
		// is linear in its length, so a target named by thousands of sources (a pipe network's
		// members, a z-level's turfs) made boot quadratic. An alist inserts in constant time.
		index = alist()
		target.om_refs_in = index
	return index

/// Drops `target`'s empty index.
/proc/_rel_index_drop_if_empty(datum/target, list/index)
	if(length(index))
		return
	if(isturf(target))
		var/turf/where = target
		var/list/by_turf = GLOB.rel_turf_index["[where.z]"]
		by_turf?.Remove(own_key(where))
	else
		target.om_refs_in = null

/proc/_rel_index(datum/target, datum/source, var_name)
	// A relation var some type's derived() hops over: join the dependency index (derived.dm). Before the
	// rel_tracked() check: a hop follows an area or a registry singleton as well.
	if(GLOB?.derived_link_vars?[var_name])
		derived_linked(source, var_name, target)
	if(!rel_tracked(target))
		return
	var/list/index = _rel_index_of(target, TRUE)
	var/source_ref = OWN_KEY(source)
	var/current = index[source_ref]
	if(isnull(current))
		if(_rel_index_prune_due(length(index)))
			_rel_index_prune(target, index)
		index[source_ref] = var_name
	else if(islist(current))
		var/list/names = current
		names |= var_name
	else if(current != var_name)
		index[source_ref] = list(current, var_name)

/// TRUE when an index of `len` sources should prune: at REL_INDEX_PRUNE_AT and each doubling of it
/// (96, 192, 384, ...). Pruning every REL_INDEX_PRUNE_AT additions made a target named by tens of
/// thousands of sources (the world native watch every rule binding names) quadratic; doubling keeps
/// it amortized constant per addition. Stale entries in between are harmless: every reader
/// re-checks that the source still names the target (rel_incoming_refs() included).
/proc/_rel_index_prune_due(len)
	if(len < REL_INDEX_PRUNE_AT || (len % REL_INDEX_PRUNE_AT))
		return FALSE
	var/multiple = len / REL_INDEX_PRUNE_AT
	return !(multiple & (multiple - 1))

/// TRUE when `source` still names `target` through one of `names` (a var name or a list of them).
/// `live_only`: a source being destroyed doesn't count (pruning); otherwise it still holds the reference.
/proc/_rel_source_names(datum/source, names, datum/target, live_only = FALSE)
	if(!isdatum(source) || (live_only && QDELETED(source)))
		return FALSE
	for(var/name in (islist(names) ? names : list(names)))
		if(!(name in source.vars))
			continue
		var/value = source.vars[name]
		if(value == target || (islist(value) && (target in value)))
			return TRUE
	return FALSE

/// Removes entries whose source no longer exists or no longer names `target` through the var.
/proc/_rel_index_prune(datum/target, list/index)
	for(var/source_ref in index.Copy())
		if(!_rel_source_names(own_locate(source_ref), index[source_ref], target, TRUE))
			index -= source_ref

/proc/_rel_unindex(datum/target, datum/source, var_name)
	if(!isdatum(target))
		return
	if(GLOB?.derived_link_vars?[var_name])
		derived_unlinked(source, var_name, target)
	var/list/index = _rel_index_of(target)
	if(!index)
		return
	var/source_ref = OWN_KEY(source)
	var/current = index[source_ref]
	if(isnull(current))
		return
	// Still named by the same var (a list view holding it twice is not possible: lists use |=).
	if(islist(current))
		var/list/names = current
		names -= var_name
		if(length(names) == 1)
			index[source_ref] = names[1]
		else if(!length(names))
			index -= source_ref
	else if(current == var_name)
		index -= source_ref
	_rel_index_drop_if_empty(target, index)

/// TRUE when source.var_name (a relation view) names `target`, read from target's reverse index in
/// constant time instead of scanning a long list view. Every framework write keeps the index in
/// step with the view, so this answers exactly as `target in source.var_name` would.
/proc/rel_names(datum/source, var_name, datum/target)
	if(!source || !target)
		return FALSE
	if(!rel_tracked(target))
		var/value = source.vars[var_name]
		return islist(value) ? (target in value) : value == target
	var/list/index = _rel_index_of(target)
	if(!index)
		return FALSE
	var/names = index[OWN_KEY(source)]
	return islist(names) ? (var_name in names) : names == var_name

/// The REF entry for source.var_name (learned as an implicit REF when undeclared; reported when
/// the var is another kind).
/proc/_rel_entry(datum/source, var_name, is_list = FALSE)
	return own_entry_of_kind(source, var_name, OWNK_REL, is_list)

// ---------------------------------------------------------------- writes

/// Points source.var_name (a single REF view) at `target`, or clears it with null. A pair view
/// sets the partner's side too; the old partner stops naming source. Returns the target.
/proc/rel_view_set(datum/source, var_name, datum/target)
	// Nothing changes (e.g. New() linking null into an empty view): no table needed, which also
	// keeps datums made during global init (before the shared caches exist) off the table.
	if(source.vars[var_name] == target)
		return target
	if(target && !own_guard(source, target, "rel_set([var_name])")) // the one teardown guard (guard.dm)
		return null
	var/list/entry = _rel_entry(source, var_name)
	if(!entry)
		source.vars[var_name] = target // ALLOW(api): undeclared view, reported above
		own_field_changed(source, var_name)
		return target
	if(entry[OWNE_LIST])
		OWN_REPORT("rel_set on list view [source.type].[var_name]: use rel_add/rel_remove")
		return null
	if(!own_type_ok(source, var_name, entry, target))
		return null
	var/datum/old = source.vars[var_name] // unchanged since the check above (_rel_entry writes no var)
	if(old)
		_rel_detach(source, var_name, old, entry)
	if(target)
		_rel_attach(source, var_name, target, entry)
	return target

/// Adds `target` to source.var_name (a list REF view). A symmetric or pair view adds the other side.
/proc/rel_view_add(datum/source, var_name, datum/target)
	var/list/entry = _rel_entry(source, var_name, TRUE)
	if(!entry || !target)
		return null
	if(!entry[OWNE_LIST])
		OWN_REPORT("rel_add on single view [source.type].[var_name]: use rel_set")
		return null
	if(!own_type_ok(source, var_name, entry, target))
		return null
	if(!own_guard(source, target, "rel_add([var_name])")) // the one teardown guard (guard.dm)
		return null
	var/list/L = source.vars[var_name]
	if(islist(L) && (target in L))
		return target
	_rel_attach(source, var_name, target, entry)
	return target

/// Removes `target` from source.var_name (list view), or clears a single view naming it.
/proc/rel_view_remove(datum/source, var_name, datum/target)
	if(!target)
		return FALSE
	var/value = source.vars[var_name]
	if(islist(value) ? !(target in value) : value != target)
		return FALSE
	// Learn the shape from the value (a remove before any add must not fix a list view as single).
	var/list/entry = _rel_entry(source, var_name, islist(value))
	if(!entry)
		return FALSE
	_rel_detach(source, var_name, target, entry)
	return TRUE

/// Links source.var_name to `target`: points a rel_one() view at it (unlinking the old one) or adds
/// it to a rel_many() view. A two-sided view (back =) writes the other side too: never write both.
/// Returns the target, or null when refused.
/proc/rel_link(datum/source, var_name, datum/target)
	var/list/entry = own_table_of(source).entries[var_name]
	if(entry ? entry[OWNE_LIST] : islist(source.vars[var_name]))
		return rel_add(source, var_name, target)
	return rel_set(source, var_name, target)

/// Unlinks `target` from source.var_name (both sides of a two-sided view), or every target when
/// `target` is null. Returns TRUE when something was unlinked.
/proc/rel_unlink(datum/source, var_name, datum/target = null)
	if(isnull(target))
		if(isnull(source.vars[var_name]))
			return FALSE
		rel_clear(source, var_name)
		return TRUE
	return rel_remove(source, var_name, target)

/// Empties source.var_name: every target unlinked (partners too).
/proc/rel_view_clear(datum/source, var_name)
	var/list/entry = own_table_of(source).entries[var_name]
	var/value = source.vars[var_name]
	if(isnull(value))
		return
	if(!entry)
		if(islist(value)) // emptied in place, not nulled: `L.len` readers keep working
			var/list/E = value
			E.Cut()
		else
			source.vars[var_name] = null // ALLOW(api): a view var no type declared: the accessor clears it and reports the missing declaration
		own_field_changed(source, var_name)
		return
	if(islist(value))
		var/list/L = value
		for(var/datum/target as anything in L.Copy())
			_rel_detach(source, var_name, target, entry)
		// The list stays (emptied), not nulled: `L.len` readers keep working.
	else
		_rel_detach(source, var_name, value, entry)

/// Links source.var_name -> target: writes the view, indexes it, and sets the partner side.
/proc/_rel_attach(datum/source, var_name, datum/target, list/entry)
	if(entry[OWNE_LIST])
		var/list/L = source.vars[var_name]
		if(!islist(L))
			L = list()
			source.vars[var_name] = L // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		// rel_add() (the only list caller) already found `target` absent: append, don't rescan.
		L += target
		own_field_changed(source, var_name) // a member added is a write: what draws or reads the list follows
	else
		source.vars[var_name] = target // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		own_field_changed(source, var_name)
	_rel_index(target, source, var_name)
	if(entry[OWNE_WATCH])
		_rel_watch(target, source)
	var/partner_var = entry[OWNE_PARTNER]
	if(!partner_var || entry[OWNE_ARG] == RELS_PLAIN || !isdatum(target))
		return
	if(!(partner_var in target.vars))
		OWN_REPORT("[source.type].[var_name]: partner [target.type] has no var '[partner_var]'")
		return
	var/list/pentry = own_table_of(target).entries[partner_var]
	if(!pentry || pentry[OWNE_KIND] != OWNK_REL)
		OWN_REPORT("[source.type].[var_name]: partner var [target.type].[partner_var] is not declared rel_one/rel_many(back =)")
		return
	var/theirs = target.vars[partner_var]
	if(pentry[OWNE_LIST])
		if(islist(theirs) && (source in theirs))
			return
		var/list/TL = theirs
		if(!islist(TL))
			TL = list()
			target.vars[partner_var] = TL // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		TL += source // absent (checked above): a pipeline's thousands of members stay linear
		own_field_changed(target, partner_var)
		_rel_index(source, target, partner_var)
		if(pentry[OWNE_WATCH])
			_rel_watch(source, target)
		return
	if(theirs == source)
		return
	if(theirs) // exclusive: the partner's old partner loses it
		_rel_detach(target, partner_var, theirs, pentry)
	target.vars[partner_var] = source // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
	own_field_changed(target, partner_var)
	_rel_index(source, target, partner_var)
	if(pentry[OWNE_WATCH])
		_rel_watch(source, target)

/// Unlinks source.var_name -> target, and the partner side when it names source.
/proc/_rel_detach(datum/source, var_name, datum/target, list/entry)
	var/value = source.vars[var_name]
	if(islist(value))
		var/list/L = value
		L -= target
		own_field_changed(source, var_name)
	else if(value == target)
		source.vars[var_name] = null // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		own_field_changed(source, var_name)
	_rel_unindex(target, source, var_name)
	if(entry?[OWNE_WATCH])
		_rel_unwatch(target, source)
	_rel_unlinked(source, target, entry)
	var/partner_var = entry?[OWNE_PARTNER]
	if(!partner_var || entry[OWNE_ARG] == RELS_PLAIN || !isdatum(target) || !(partner_var in target.vars))
		return
	var/theirs = target.vars[partner_var]
	var/unlinked = FALSE
	if(islist(theirs))
		var/list/TL = theirs
		if(source in TL)
			TL -= source
			own_field_changed(target, partner_var)
			_rel_unindex(source, target, partner_var)
			unlinked = TRUE
	else if(theirs == source)
		target.vars[partner_var] = null // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		own_field_changed(target, partner_var)
		_rel_unindex(source, target, partner_var)
		unlinked = TRUE
	if(!unlinked)
		return
	var/list/pentry = own_table_of(target).entries[partner_var]
	if(pentry?[OWNE_WATCH])
		_rel_unwatch(source, target)
	_rel_unlinked(target, source, pentry)

/// A link of holder's view (declared by `entry`) to `other` just went: runs the view's on_unlink
/// hook (rel_one/rel_many(on_unlink = PROC_REF(x))) as holder.x(other). A holder being destroyed
/// is not told: its own teardown releases everything.
/proc/_rel_unlinked(datum/holder, datum/other, list/entry)
	var/hook = entry?[OWNE_ON_UNLINK]
	if(!hook || QDELETED(holder))
		return
	call(holder, hook)(other)

/// `watcher` has a watched view naming `target`: state_changed(target) now marks `watcher` too.
/proc/_rel_watch(datum/target, datum/watcher)
	if(!isdatum(target) || !isdatum(watcher))
		return
	var/key = OWN_KEY(watcher)
	LAZYINITLIST(target.rel_watchers)
	target.rel_watchers[key] = (target.rel_watchers[key] || 0) + 1

/// One watched view of `watcher` stopped naming `target`.
/proc/_rel_unwatch(datum/target, datum/watcher)
	if(!isdatum(target) || !isdatum(watcher) || !target.rel_watchers)
		return
	var/key = OWN_KEY(watcher)
	var/count = target.rel_watchers[key]
	if(count > 1)
		target.rel_watchers[key] = count - 1
	else
		target.rel_watchers -= key
		UNSETEMPTY(target.rel_watchers)

/// `watcher` reads `target` in an output (look.watch()): state_changed(target) marks `watcher` too, until rel_unobserve() takes it back. One call,
/// one count, like a watched view; the caller pairs them (the look's subscription follows the draw).
/proc/rel_observe(datum/target, datum/watcher)
	_rel_watch(target, watcher)

/proc/rel_unobserve(datum/target, datum/watcher)
	_rel_unwatch(target, watcher)

/// state_changed() raised on `target`: marks every live source that watches it through a relation view.
/proc/rel_notify_watchers(datum/target)
	for(var/key in target.rel_watchers)
		var/datum/watcher = own_locate(key)
		if(isdatum(watcher) && !QDELING(watcher))
			state_changed(watcher)

// ---------------------------------------------------------------- reads

/// Every live target of source.var_name as a list (a shared empty list when none; never write it).
/proc/rel_targets(datum/source, var_name)
	var/static/list/empty = list()
	var/value = source.vars[var_name]
	if(islist(value))
		return value
	return isnull(value) ? empty : list(value)

/// Every source whose REF var names `target`, as a list of list(source, var name).
/proc/rel_sources(datum/target)
	. = list()
	var/list/index = target ? _rel_index_of(target) : null
	for(var/source_ref in index)
		var/datum/S = own_locate(source_ref)
		if(!isdatum(S))
			continue
		var/names = index[source_ref]
		for(var/name in (islist(names) ? names : list(names)))
			. += list(list(S, name))

/// Every source whose var `var_name` names `target`, as a list: the reverse index read for one var (a one-ended link needs no var on the
/// target's type). Empty when none; a fresh list.
/proc/rel_sources_via(datum/target, var_name)
	READS_FROM(target)
	. = list()
	for(var/list/pair as anything in rel_sources(target))
		if(pair[2] == var_name)
			. += pair[1]

/// How many references to `target` relation views hold (one per single view, one per list view
/// holding it). For refcount accounting (latent collapse).
/proc/rel_incoming_refs(datum/target)
	. = 0
	var/list/index = target ? _rel_index_of(target) : null
	for(var/source_ref in index)
		var/datum/S = own_locate(source_ref)
		var/names = index[source_ref]
		// Only live entries count (an index may hold stale ones between prunes).
		for(var/name in (islist(names) ? names : list(names)))
			if(_rel_source_names(S, name, target))
				.++

// ---------------------------------------------------------------- lifecycle

/// Phase 4: `D` is dying. Every view naming it is cleared (sources), then every view it holds
/// stops being indexed on its targets, and its partners stop naming it.
/proc/rel_teardown(datum/D)
	var/list/doomed
	D.rel_watchers = null // its watchers' views are cleared below with the rest of the index
	// D is a target no hop can follow any more (its sources are cleared below).
	if(D.own_key_text && GLOB?.derived_watch?[D.own_key_text])
		GLOB.derived_watch -= D.own_key_text
	var/list/index = D.om_refs_in
	if(index)
		D.om_refs_in = null
		for(var/source_ref in index)
			var/datum/S = own_locate(source_ref)
			if(!isdatum(S) || S == D)
				continue
			var/names = index[source_ref]
			for(var/name in (islist(names) ? names : list(names)))
				if(!(name in S.vars))
					continue
				var/value = S.vars[name]
				var/dropped = FALSE
				if(value == D)
					S.vars[name] = null // ALLOW(api): relation teardown clears the view var; the relation machinery is the accessor
					own_field_changed(S, name)
					dropped = TRUE
				else if(islist(value))
					var/list/L = value
					if(D in L)
						L -= D
						dropped = TRUE
				if(!dropped)
					continue
				var/list/sentry = own_table_of(S).entries[name]
				if(!sentry)
					continue
				_rel_unlinked(S, D, sentry)
				if(sentry[OWNE_OTHER_DELETED] == DELETE_ME && !QDELETED(S))
					LAZYOR(doomed, S)
	// other_deleted = DELETE_ME: the holders go with D, once every view naming D is cleared.
	for(var/datum/S as anything in doomed)
		if(!QDELETED(S))
			ended_with(S, D)
	var/datum/own_table/T = own_table_of(D)
	for(var/var_name in T.ref_vars)
		var/value = D.vars[var_name]
		if(isnull(value))
			continue
		var/list/entry = T.entries[var_name]
		if(islist(value))
			var/list/L = value
			for(var/datum/target as anything in L.Copy())
				_rel_detach(D, var_name, target, entry)
			D.vars[var_name] = null // ALLOW(api): relation teardown clears the view var; the relation machinery is the accessor
			own_field_changed(D, var_name)
		else
			_rel_detach(D, var_name, value, entry)

/// z-level release: every relation view naming a turf on `z` is cleared. Returns how many.
/proc/rel_drop_z(z)
	var/zkey = "[z]"
	var/list/by_turf = GLOB.rel_turf_index[zkey]
	if(!by_turf)
		return 0
	GLOB.rel_turf_index -= zkey
	. = 0
	for(var/turf_ref in by_turf)
		var/turf/T = own_locate(turf_ref)
		var/list/index = by_turf[turf_ref]
		if(!isturf(T))
			continue
		for(var/source_ref in index)
			var/datum/S = own_locate(source_ref)
			if(!isdatum(S))
				continue
			var/names = index[source_ref]
			for(var/name in (islist(names) ? names : list(names)))
				if(!(name in S.vars))
					continue
				var/value = S.vars[name]
				if(value == T)
					S.vars[name] = null // ALLOW(api): releasing a z-level clears the view var; the relation machinery is the accessor
					own_field_changed(S, name)
					.++
				else if(islist(value))
					var/list/views = value
					if(T in views)
						views -= T
						.++

// ---------------------------------------------------------------- latent identity

/// `D` is collapsing into latent data but keeps its handle slot: every view naming it goes
/// dormant under that handle instead of being lost, and re-links in rel_wake().
/proc/rel_go_dormant(datum/D)
	var/list/index = D.om_refs_in
	var/h = D.om_hid
	if(!index || !h)
		return
	var/list/dormant = GLOB.rel_dormant["[h]"]
	if(!dormant)
		dormant = list()
		GLOB.rel_dormant["[h]"] = dormant
	for(var/source_ref in index)
		var/datum/S = own_locate(source_ref)
		var/names = index[source_ref]
		for(var/name in (islist(names) ? names : list(names)))
			if(_rel_source_names(S, name, D)) // a stale entry (between prunes) is not a view
				dormant += list(source_ref, name)

/// `D` re-materialized into handle slot `h`: the dormant views re-link to it.
/proc/rel_wake(datum/D, h)
	var/list/dormant = GLOB.rel_dormant["[h]"]
	if(!dormant)
		return
	GLOB.rel_dormant -= "[h]"
	for(var/i in 1 to length(dormant) step 2)
		var/datum/S = own_locate(dormant[i])
		var/name = dormant[i + 1]
		if(!isdatum(S) || QDELETED(S) || !(name in S.vars))
			continue
		var/list/entry = own_table_of(S).entries[name]
		if(!entry)
			continue
		if(entry[OWNE_LIST])
			rel_add(S, name, D)
		else if(isnull(S.vars[name]))
			rel_set(S, name, D)

// ---------------------------------------------------------------- replace_with identity

/// The type family a replace_with() successor must belong to for `original`'s identity (handle
/// slot and relation views) to follow it: the original's type cut to its first three path
/// elements (/obj/machinery/door, /obj/item/clothing, /mob/living/carbon). A registry or holder
/// view naming an airlock means "this airlock" as a machine; the door_assembly or steel stack it
/// is torn down into is not one, and would answer procs the holder calls on it with runtimes.
/proc/rel_forward_family(datum/original)
	var/list/parts = splittext("[original.type]", "/")
	if(length(parts) > 4)
		parts.Cut(5)
	return text2path(jointext(parts, "/"))

/// TRUE when `successor` is the same kind of thing as `original` (rel_forward_family()).
/proc/rel_forward_compatible(datum/original, datum/successor)
	var/family = rel_forward_family(original)
	return !family || istype(successor, family)

/// replace_with(): `successor` takes over `original`'s identity before the original is destroyed.
/// Identity follows only a successor of the same family (rel_forward_compatible()):
/// - its handle slot (old handles resolve to the successor), unless the successor has its own;
/// - every relation view naming the original re-links to the successor;
/// otherwise the original's handle and views end with it, as in any destroy. Always:
/// - its FORWARD_STATE vars: an owned value moves, a relation view re-links, a value is copied.
/proc/rel_forward_identity(datum/original, datum/successor)
	if(!original || !successor || original == successor)
		return
	if(!rel_forward_compatible(original, successor))
		if(GLOB.dq_lifecycle_trace_depth)
			log_world("LIFECYCLE_TRACE: [original.type] [ref(original)] replace_with: successor [successor.type] is outside family [rel_forward_family(original)]; handle and views end with the original")
		rel_forward_state(original, successor)
		return
	var/id = original.om_hid
	if(id && !successor.om_hid)
		var/list/slots = GLOB.om_handle_slots
		if(id <= length(slots) && slots[id] == own_key(original))
			slots[id] = own_key(successor)
			var/list/types = GLOB.om_handle_types
			if(length(types) >= id)
				types[id] = successor.type
			successor.om_hid = id
			original.om_hid = 0
	for(var/list/pair as anything in rel_sources(original))
		var/datum/S = pair[1]
		var/name = pair[2]
		if(S == original || S == successor || QDELETED(S))
			continue
		var/list/entry = own_table_of(S).entries[name]
		if(!entry)
			continue
		if(entry[OWNE_LIST])
			rel_remove(S, name, original)
			rel_add(S, name, successor)
		else if(S.vars[name] == original)
			rel_set(S, name, successor)
	rel_forward_state(original, successor)

/// replace_with(): carries `original`'s forward-annotated vars (own/rel/..., forward = TRUE) to
/// `successor` (rel_forward_identity()).
/proc/rel_forward_state(datum/original, datum/successor)
	for(var/name in own_table_of(original).forward_vars)
		if(!(name in successor.vars))
			continue
		var/value = original.vars[name]
		var/list/entry = own_table_of(original).entries[name]
		switch(entry?[OWNE_KIND])
			if(OWNK_OWN)
				for(var/datum/child as anything in own_values(original, name))
					own_move(child, successor, name)
			if(OWNK_REL)
				var/list/targets = rel_targets(original, name)
				for(var/datum/target as anything in targets.Copy())
					if(islist(successor.vars[name]) || entry[OWNE_LIST])
						rel_add(successor, name, target)
					else
						rel_set(successor, name, target)
			else
				if(islist(value))
					var/list/L = value
					value = L.Copy()
				successor.vars[name] = value // ALLOW(api): declared forwarded state
				own_field_changed(successor, name)

// ---------------------------------------------------------------- keyed auto-linking

/// Target type path (text) -> key value (text) -> list of target keys (own_key()).
GLOBAL_LIST_EMPTY(rel_key_targets)
/// Target type path (text) -> key value (text) -> flat list (source key, var name).
GLOBAL_LIST_EMPTY(rel_key_waiters)

/// On materialize: index src as a keyed target, and link src's keyed views.
/proc/rel_keyed_materialize(datum/D)
	var/key_var = own_table_of(D).keyed_key
	if(key_var && !isnull(D.vars[key_var]))
		var/key = "[D.vars[key_var]]"
		for(var/path in rel_keyed_type_chain(D.type))
			var/list/by_key = GLOB.rel_key_targets[path]
			if(!by_key)
				by_key = list()
				GLOB.rel_key_targets[path] = by_key
			var/list/refs = by_key[key]
			if(!refs)
				refs = list()
				by_key[key] = refs
			refs |= own_key(D)
			var/list/waiting = GLOB.rel_key_waiters[path]?[key]
			for(var/i in 1 to length(waiting) step 2)
				var/datum/S = own_locate(waiting[i])
				if(isdatum(S) && !QDELETED(S))
					rel_keyed_link(S, waiting[i + 1], D)
	var/datum/own_table/T = own_table_of(D)
	for(var/var_name in T.keyed_vars)
		var/list/entry = T.entries[var_name]
		var/list/spec = entry[OWNE_EXTRA]
		var/our_key = D.vars[spec[2]]
		if(isnull(our_key))
			continue
		var/key = "[our_key]"
		var/path = "[spec[1]]"
		var/list/waiters_by_key = GLOB.rel_key_waiters[path]
		if(!waiters_by_key)
			waiters_by_key = list()
			GLOB.rel_key_waiters[path] = waiters_by_key
		var/list/waiting = waiters_by_key[key]
		if(!waiting)
			waiting = list()
			waiters_by_key[key] = waiting
		waiting += list(own_key(D), var_name)
		for(var/target_ref in GLOB.rel_key_targets[path]?[key])
			var/datum/target = own_locate(target_ref)
			if(isdatum(target) && !QDELETED(target))
				rel_keyed_link(D, var_name, target)

/proc/rel_keyed_link(datum/S, var_name, datum/target)
	var/list/entry = own_table_of(S).entries[var_name]
	if(!entry)
		return
	if(entry[OWNE_LIST])
		rel_add(S, var_name, target)
	else if(isnull(S.vars[var_name]))
		rel_set(S, var_name, target)

/// On dematerialize: leave the keyed indexes (views naming D clear when it dies; a view to a
/// dematerialized target is cleared here too, since it left the world).
/proc/rel_keyed_dematerialize(datum/D)
	var/key_var = own_table_of(D).keyed_key
	if(key_var && !isnull(D.vars[key_var]))
		var/key = "[D.vars[key_var]]"
		for(var/path in rel_keyed_type_chain(D.type))
			var/list/refs = GLOB.rel_key_targets[path]?[key]
			refs?.Remove(own_key(D))
	var/datum/own_table/T = own_table_of(D)
	for(var/var_name in T.keyed_vars)
		var/list/entry = T.entries[var_name]
		var/list/spec = entry[OWNE_EXTRA]
		var/our_key = D.vars[spec[2]]
		if(isnull(our_key))
			continue
		var/list/waiting = GLOB.rel_key_waiters["[spec[1]]"]?["[our_key]"]
		if(!waiting)
			continue
		var/self_ref = own_key(D)
		for(var/i = length(waiting) - 1, i >= 1, i -= 2)
			if(waiting[i] == self_ref && waiting[i + 1] == var_name)
				waiting.Cut(i, i + 2)

/// "/obj/machinery/door/blast" -> its path and every ancestor path, as text (cached per type).
/proc/rel_keyed_type_chain(path)
	var/static/list/chains = list()
	var/list/chain = chains[path]
	if(chain)
		return chain
	chain = list()
	var/current = path
	while(current && current != /datum)
		chain += "[current]"
		current = type2parent(current)
	chains[path] = chain
	return chain

/// An id can change at runtime (multitool, construction prompts): set it through keyed_set_id() so
/// the old keyed links drop and the new ones form.
/// Sets D's id var `key_var` to `new_value` and re-links every keyed relation that matches on it,
/// whether D is a keyed source keyed by that var or a keyed target indexed by it.
/proc/keyed_set_id(datum/D, key_var, new_value)
	if(!D || D.vars[key_var] == new_value)
		return
	var/materialized = isatom(D) && !QDELETED(D)
	if(materialized)
		rel_keyed_dematerialize(D)
	// As a target: sources linked to D through their keyed views drop it.
	if(own_table_of(D).keyed_key == key_var)
		for(var/list/pair as anything in rel_sources(D))
			var/datum/source = pair[1]
			var/list/entry = own_table_of(source).entries[pair[2]]
			if(entry && entry[OWNE_EXTRA])
				rel_remove(source, pair[2], D)
	// As a source: its views keyed by this var drop their targets.
	var/datum/own_table/T = own_table_of(D)
	for(var/var_name in T.keyed_vars)
		var/list/spec = T.entries[var_name][OWNE_EXTRA]
		if(spec[2] == key_var)
			rel_clear(D, var_name)
	D.vars[key_var] = new_value // ALLOW(api): the keyed-link accessor writes the id var it re-keys
	own_field_changed(D, key_var)
	if(materialized)
		rel_keyed_materialize(D)
