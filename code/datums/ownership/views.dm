// Light relation edges: REF views (doc/rewrite/ownership.md §4.1).
//
// A REF var holds a direct reference (reads are free). The target keeps a lazy reverse index,
// `om_refs_in`: the source's ref text -> the var name (or a list of var names) naming it. The
// index is weak (ref text), so source and target never form a reference cycle. When either end
// dies the framework clears its side; nothing is kept by hand.
//
// Targets that never die need no index: registry singletons (REGISTRY_TYPE) and areas. Turfs
// are indexed per z-level (ChangeTurf resets a turf's vars), and rel_drop_z() clears them when
// the z-level is released.

/// Reverse index: source ref text -> var name, or a list of var names.
/datum/var/tmp/list/om_refs_in

/// z (text) -> turf ref text -> that turf's reverse index (as om_refs_in). A turf keeps no index of
/// its own: ChangeTurf() resets its vars, while its ref (its position) stays.
GLOBAL_LIST_EMPTY(rel_turf_index)
/// Handle id (text) -> flat list, stride 2: source ref text, var name. Edges to an entity that
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

/// `target`'s reverse index (source ref text -> var name or list of names), made when `create`.
/proc/_rel_index_of(datum/target, create = FALSE)
	if(isturf(target))
		var/turf/where = target
		var/zkey = "[where.z]"
		var/list/by_turf = GLOB.rel_turf_index[zkey]
		if(!by_turf)
			if(!create)
				return null
			by_turf = list()
			GLOB.rel_turf_index[zkey] = by_turf
		var/tkey = ref(where)
		var/list/index = by_turf[tkey]
		if(!index && create)
			index = list()
			by_turf[tkey] = index
		return index
	var/list/index = target.om_refs_in
	if(!index && create)
		index = list()
		target.om_refs_in = index
	return index

/// Drops `target`'s empty index.
/proc/_rel_index_drop_if_empty(datum/target, list/index)
	if(length(index))
		return
	if(isturf(target))
		var/turf/where = target
		var/list/by_turf = GLOB.rel_turf_index["[where.z]"]
		by_turf?.Remove(ref(where))
	else
		target.om_refs_in = null

/proc/_rel_index(datum/target, datum/source, var_name)
	if(!rel_tracked(target))
		return
	var/list/index = _rel_index_of(target, TRUE)
	var/source_ref = ref(source)
	var/current = index[source_ref]
	if(isnull(current))
		if(length(index) >= REL_INDEX_PRUNE_AT && !(length(index) % REL_INDEX_PRUNE_AT))
			_rel_index_prune(target, index)
		index[source_ref] = var_name
	else if(islist(current))
		var/list/names = current
		names |= var_name
	else if(current != var_name)
		index[source_ref] = list(current, var_name)

/// Removes entries whose source no longer exists or no longer names `target` through the var.
/proc/_rel_index_prune(datum/target, list/index)
	for(var/source_ref in index.Copy())
		var/datum/S = locate(source_ref)
		var/names = index[source_ref]
		var/keep = FALSE
		if(isdatum(S) && !QDELETED(S))
			for(var/name in (islist(names) ? names : list(names)))
				if(!(name in S.vars))
					continue
				var/value = S.vars[name]
				if(value == target || (islist(value) && (target in value)))
					keep = TRUE
					break
		if(!keep)
			index -= source_ref

/proc/_rel_unindex(datum/target, datum/source, var_name)
	if(!isdatum(target))
		return
	var/list/index = _rel_index_of(target)
	if(!index)
		return
	var/source_ref = ref(source)
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

/// The REF entry for source.var_name (learned as an implicit REF when undeclared; reported when
/// the var is another kind).
/proc/_rel_entry(datum/source, var_name, is_list = FALSE)
	return own_entry_of_kind(source, var_name, OWNK_REL, is_list)

// ---------------------------------------------------------------- writes

/// Points source.var_name (a single REF view) at `target`, or clears it with null. A pair view
/// sets the partner's side too; the old partner stops naming source. Returns the target.
/proc/rel_set(datum/source, var_name, datum/target)
	// Nothing changes (e.g. New() linking null into an empty view): no table needed, which also
	// keeps datums made during global init (before the shared caches exist) off the table.
	if(source.vars[var_name] == target)
		return target
	var/list/entry = _rel_entry(source, var_name)
	if(!entry)
		source.vars[var_name] = target // ALLOW(api, ownership): undeclared view, reported above
		own_field_changed(source, var_name)
		return target
	if(entry[OWNE_LIST])
		OWN_REPORT("rel_set on list view [source.type].[var_name]: use rel_add/rel_remove")
		return null
	var/datum/old = source.vars[var_name]
	if(old == target)
		return target
	if(target && QDELETED(target))
		OWN_REPORT("[source.type].[var_name]: refusing a link to [target.type], which is being destroyed")
		target = null
	if(old)
		_rel_detach(source, var_name, old, entry)
	if(target)
		_rel_attach(source, var_name, target, entry)
	return target

/// Adds `target` to source.var_name (a list REF view). A symmetric or pair view adds the other side.
/proc/rel_add(datum/source, var_name, datum/target)
	var/list/entry = _rel_entry(source, var_name, TRUE)
	if(!entry || !target)
		return null
	if(!entry[OWNE_LIST])
		OWN_REPORT("rel_add on single view [source.type].[var_name]: use rel_set")
		return null
	if(QDELETED(target))
		OWN_REPORT("[source.type].[var_name]: refusing a link to [target.type], which is being destroyed")
		return null
	var/list/L = source.vars[var_name]
	if(islist(L) && (target in L))
		return target
	_rel_attach(source, var_name, target, entry)
	return target

/// Removes `target` from source.var_name (list view), or clears a single view naming it.
/proc/rel_remove(datum/source, var_name, datum/target)
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

/// Empties source.var_name: every target unlinked (partners too).
/proc/rel_clear(datum/source, var_name)
	var/list/entry = own_table_of(source).entries[var_name]
	var/value = source.vars[var_name]
	if(isnull(value))
		return
	if(!entry)
		if(islist(value)) // emptied in place, not nulled: `L.len` readers keep working
			var/list/E = value
			E.Cut()
		else
			source.vars[var_name] = null // ALLOW(api, ownership): undeclared view
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
			source.vars[var_name] = L // ALLOW(api, ownership): the accessor
			own_field_changed(source, var_name)
		L |= target
	else
		source.vars[var_name] = target // ALLOW(api, ownership): the accessor
		own_field_changed(source, var_name)
	_rel_index(target, source, var_name)
	var/partner_var = entry[OWNE_PARTNER]
	if(!partner_var || entry[OWNE_ARG] == RELS_PLAIN || !isdatum(target))
		return
	if(!(partner_var in target.vars))
		OWN_REPORT("[source.type].[var_name]: partner [target.type] has no var '[partner_var]'")
		return
	var/list/pentry = own_table_of(target).entries[partner_var]
	if(!pentry || pentry[OWNE_KIND] != OWNK_REL)
		OWN_REPORT("[source.type].[var_name]: partner var [target.type].[partner_var] is not declared REL_PAIR/REL_SET")
		return
	var/theirs = target.vars[partner_var]
	if(pentry[OWNE_LIST])
		if(islist(theirs) && (source in theirs))
			return
		var/list/TL = theirs
		if(!islist(TL))
			TL = list()
			target.vars[partner_var] = TL // ALLOW(api, ownership): the accessor
			own_field_changed(target, partner_var)
		TL |= source
		_rel_index(source, target, partner_var)
		return
	if(theirs == source)
		return
	if(theirs) // exclusive: the partner's old partner loses it
		_rel_detach(target, partner_var, theirs, pentry)
	target.vars[partner_var] = source // ALLOW(api, ownership): the accessor
	own_field_changed(target, partner_var)
	_rel_index(source, target, partner_var)

/// Unlinks source.var_name -> target, and the partner side when it names source.
/proc/_rel_detach(datum/source, var_name, datum/target, list/entry)
	var/value = source.vars[var_name]
	if(islist(value))
		var/list/L = value
		L -= target
	else if(value == target)
		source.vars[var_name] = null // ALLOW(api, ownership): the accessor
		own_field_changed(source, var_name)
	_rel_unindex(target, source, var_name)
	var/partner_var = entry?[OWNE_PARTNER]
	if(!partner_var || entry[OWNE_ARG] == RELS_PLAIN || !isdatum(target) || !(partner_var in target.vars))
		return
	var/theirs = target.vars[partner_var]
	if(islist(theirs))
		var/list/TL = theirs
		if(source in TL)
			TL -= source
			_rel_unindex(source, target, partner_var)
	else if(theirs == source)
		target.vars[partner_var] = null // ALLOW(api, ownership): the accessor
		own_field_changed(target, partner_var)
		_rel_unindex(source, target, partner_var)

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
		var/datum/S = locate(source_ref)
		if(!isdatum(S))
			continue
		var/names = index[source_ref]
		for(var/name in (islist(names) ? names : list(names)))
			. += list(list(S, name))

/// How many references to `target` relation views hold (one per single view, one per list view
/// holding it). For refcount accounting (latent collapse).
/proc/rel_incoming_refs(datum/target)
	. = 0
	var/list/index = target ? _rel_index_of(target) : null
	for(var/source_ref in index)
		var/names = index[source_ref]
		. += islist(names) ? length(names) : 1

// ---------------------------------------------------------------- lifecycle

/// Phase 4: `D` is dying. Every view naming it is cleared (sources), then every view it holds
/// stops being indexed on its targets, and its partners stop naming it.
/proc/rel_teardown(datum/D)
	var/list/index = D.om_refs_in
	if(index)
		D.om_refs_in = null
		for(var/source_ref in index)
			var/datum/S = locate(source_ref)
			if(!isdatum(S) || S == D)
				continue
			var/names = index[source_ref]
			for(var/name in (islist(names) ? names : list(names)))
				if(!(name in S.vars))
					continue
				var/value = S.vars[name]
				if(value == D)
					S.vars[name] = null // ALLOW(api, ownership): relation teardown
					own_field_changed(S, name)
				else if(islist(value))
					var/list/L = value
					L -= D
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
			D.vars[var_name] = null // ALLOW(api, ownership): relation teardown
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
		var/turf/T = locate(turf_ref)
		var/list/index = by_turf[turf_ref]
		if(!isturf(T))
			continue
		for(var/source_ref in index)
			var/datum/S = locate(source_ref)
			if(!isdatum(S))
				continue
			var/names = index[source_ref]
			for(var/name in (islist(names) ? names : list(names)))
				if(!(name in S.vars))
					continue
				var/value = S.vars[name]
				if(value == T)
					S.vars[name] = null // ALLOW(api, ownership): z-level release
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
		var/names = index[source_ref]
		for(var/name in (islist(names) ? names : list(names)))
			dormant += list(source_ref, name)

/// `D` re-materialized into handle slot `h`: the dormant views re-link to it.
/proc/rel_wake(datum/D, h)
	var/list/dormant = GLOB.rel_dormant["[h]"]
	if(!dormant)
		return
	GLOB.rel_dormant -= "[h]"
	for(var/i in 1 to length(dormant) step 2)
		var/datum/S = locate(dormant[i])
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

/// replace_with(): `successor` takes over `original`'s identity before the original is destroyed.
/// - its handle slot (old handles resolve to the successor), unless the successor has its own;
/// - every relation view naming the original re-links to the successor;
/// - its FORWARD_STATE vars: an owned value moves, a relation view re-links, a value is copied.
/proc/om_handle_forward(datum/original, datum/successor)
	if(!original || !successor || original == successor)
		return
	var/id = original.om_hid
	if(id && !successor.om_hid)
		var/list/slots = GLOB.om_handle_slots
		if(id <= length(slots) && slots[id] == REF(original))
			slots[id] = REF(successor)
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
	for(var/name in original.declared_forward_vars())
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
				successor.vars[name] = value // ALLOW(api, ownership): declared forwarded state
				own_field_changed(successor, name)

// ---------------------------------------------------------------- keyed auto-linking

/// Target type path (text) -> key value (text) -> list of target ref texts.
GLOBAL_LIST_EMPTY(rel_key_targets)
/// Target type path (text) -> key value (text) -> flat list (source ref text, var name).
GLOBAL_LIST_EMPTY(rel_key_waiters)

/// KEYED_TARGET(PATH, KEY_VAR): the var REL_KEYED sources match against, or null.
/datum/proc/keyed_target_var()
	return null

/// On materialize: index src as a keyed target, and link src's keyed views.
/proc/rel_keyed_materialize(datum/D)
	var/key_var = D.keyed_target_var()
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
			refs |= ref(D)
			var/list/waiting = GLOB.rel_key_waiters[path]?[key]
			for(var/i in 1 to length(waiting) step 2)
				var/datum/S = locate(waiting[i])
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
		waiting += list(ref(D), var_name)
		for(var/target_ref in GLOB.rel_key_targets[path]?[key])
			var/datum/target = locate(target_ref)
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
	var/key_var = D.keyed_target_var()
	if(key_var && !isnull(D.vars[key_var]))
		var/key = "[D.vars[key_var]]"
		for(var/path in rel_keyed_type_chain(D.type))
			var/list/refs = GLOB.rel_key_targets[path]?[key]
			refs?.Remove(ref(D))
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
		var/self_ref = ref(D)
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
/// whether D is a REL_KEYED source keyed by that var or a KEYED_TARGET indexed by it.
/proc/keyed_set_id(datum/D, key_var, new_value)
	if(!D || D.vars[key_var] == new_value)
		return
	var/materialized = isatom(D) && !QDELETED(D)
	if(materialized)
		rel_keyed_dematerialize(D)
	// As a target: sources linked to D through their keyed views drop it.
	if(D.keyed_target_var() == key_var)
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
	D.vars[key_var] = new_value // ALLOW(api, ownership): the keyed-link accessor writes the id var it re-keys
	own_field_changed(D, key_var)
	if(materialized)
		rel_keyed_materialize(D)
