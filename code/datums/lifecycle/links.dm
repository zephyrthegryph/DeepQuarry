// L2: the links framework (roadmap L track, doc/rewrite/lifecycle.md §4).
//
// Every object-typed var on a datum is declared as exactly one kind:
//   - slot content            containment (ledger.dm/lifecycle.dm) -- not this file
//   - REF_OWNED / REF_OWNED_LIST   a child that isn't contained, deleted in phase 4
//   - REF_PAIR                 two-sided; link_set()/link_clear() keep both sides in sync
//   - REF_BACKLIST             membership in another object's list, removed automatically
//   - handle (om_handle())     the default for everything else -- resolved on read, never cleaned
//   - tmp cache                recomputable; scrubbed in phase 8
//   - REF_DEF                  a frozen definition or registry object: nothing to clear
//   - REF_TRANSIENT            a pooled object's per-use field, reset by pool_release()
//
// A type declares its kinds by overriding one or more of the four procs
// below, each returning a proc-local `var/static/list` (the usual pattern
// for a per-type constant table this codebase can't express as a class var,
// e.g. slot_def_types()). The per-type table is then built once, lazily, the
// first time link_table_for() sees the type -- the same lazy-once-per-type
// cache dq_slot_defs_for() already uses, which this codebase already treats
// as its "boot-time" table pattern (built on first real use, not literally
// during SSinit, so a type nobody ever destroys never pays for a table).
//
// The lint (tools/ci/declared_refs_lint.py) is what actually enforces "every
// object-typed var is declared as exactly one kind" -- checked statically
// against these four procs plus slot_def_types(), ratcheted, with DQ
// Medical's areas (body, organs, afflictions, surgery, protean) allow-listed
// until they convert (doc §4, §7).

/// Names of `src`'s own (not contained) child object vars: each is QDEL_NULL'd
/// in phase 4, then (defensively) nulled again in phase 8 if leftover
/// Destroy() re-set one. Var names only -- resolved with vars[] at phase time.
/datum/proc/declared_owned_vars()
	return null

/// Names of `src`'s own list vars of children: each is QDEL_LIST'd in phase 4.
/datum/proc/declared_owned_list_vars()
	return null

/// Names of `src`'s own assoc list vars whose *values* are children (keyed by
/// id): each value is deleted in phase 4 (was QDEL_LIST_ASSOC_VAL).
/datum/proc/declared_owned_value_vars()
	return null

/// Assoc: our var name -> the *other* object's var name that points back to
/// us. Declaring this on both sides (A's entry says "b_var", B's says
/// "a_var") is what makes link_set()/link_clear() find the reciprocal var
/// without walking every var on the other object. A pair var not currently
/// set is simply null; declaring it costs nothing until it's used.
/datum/proc/declared_pair_vars()
	return null

/// Assoc: our var name (a reference to the object whose list we're a member
/// of) -> that object's list var name. Phase 4 removes `src` from
/// `owner.vars[list_var]` for each declared entry whose owner var is set.
/datum/proc/declared_backlist_vars()
	return null

/// Assoc: our var holding an OM HANDLE to the owner -> the owner's list var
/// that holds us (REF_BACKLIST_HANDLE). Phase 4 resolves the handle and removes
/// us (or our handle) from that list; the handle var itself is left (text).
/datum/proc/declared_backlist_handle_vars()
	return null

/// Assoc: our var holding an OM HANDLE to a partner -> the partner's var that
/// names us back (REF_BACK_HANDLE). Phase 4 resolves the handle and nulls the
/// partner's var if it still names us, by reference or by handle.
/datum/proc/declared_back_handle_vars()
	return null

/// Assoc: a path to a partner -> the partner's var(s) that name us (REF_BACK_VIA).
/// The path is one var name or several joined by "." ("master_handle.cl_handle"),
/// read hop by hop from src; each hop may hold a reference or an OM handle. The
/// value is a var name, a list of them, or list(/partner/type = name or names)
/// (lifecycle_backlist_handle_lists()). Phase 4 finds the partner and, for each
/// named var: a list loses us (and our handle); anything else naming us (by
/// reference or handle) is nulled. Our own vars are left alone.
/datum/proc/declared_back_via_vars()
	return null

/// Assoc: our list var -> the member var(s) that name us back (REF_LIST_BACK): the
/// owner side of a back-list. Phase 4 visits each member (keys and assoc values,
/// references or OM handles) and, for each named var, removes us from it if it is a
/// list or nulls it if it names us. The list itself is dropped once the links clear.
/datum/proc/declared_list_back_vars()
	return null

/// Names of `src`'s vars simply dropped in phase 4 (REF_DROP): the target is not
/// deleted, not cut and not told. For scratch tables keyed by other objects and
/// lists src was handed (and may share), which only must stop pinning their contents.
/datum/proc/declared_drop_vars()
	return null

/// Assoc: a var of src that says whether src is queued (or LIFECYCLE_QUEUE_ALWAYS)
/// -> a global proc path, or a list of them, returning the list src sits in
/// (REF_QUEUE_MEMBER): a subsystem work queue, or a global list that isn't an OM
/// registry. Phase 4 removes src from each list whose flag var is set.
/datum/proc/declared_queue_vars()
	return null

/// Names of `src`'s vars holding one inserted thing (a beaker, a card, a
/// charging cell) that goes back to the room when src is destroyed: phase 3
/// moves it to src's drop location if it is still inside src. The one-thing
/// SPILL slot, for holders that have no ledger slots.
/datum/proc/declared_spill_vars()
	return null

/// Names of `src`'s vars that name a thing it holds in its contents without a
/// destroy policy of their own (a machine's installed board). Like the owned
/// and spill vars, they are nulled when that thing is destroyed while still
/// inside src (dq_lifecycle_release_from_holder()).
/datum/proc/declared_held_vars()
	return null

/// Names of `src`'s weak list vars (REF_WEAK_LIST): lists of OM handles naming
/// other live entities src doesn't own. Phase 4 cuts them; members are untouched.
/datum/proc/declared_weak_list_vars()
	return null

/// Runs in the destroy transaction just before phase 4 (links) nulls, deletes and
/// unlinks the declared vars: the place for teardown that must still read them
/// (a holder ending its busy state, a hologram handing bellies back to its master,
/// a projectile drawing its tracers from owned beam segments). Must not sleep.
/datum/proc/lifecycle_prerelease()
	return

/// The live entities weak list `L` (REF_WEAK_LIST) names, in order. Prunes the
/// handles of deleted members from `L` in place.
/proc/weak_list_live(list/L)
	. = list()
	if(!length(L))
		return
	var/list/dead
	for(var/h in L)
		var/datum/D = om_resolve(h)
		if(D)
			. += D
		else
			LAZYADD(dead, h)
	if(dead)
		L -= dead

/// Names of `src`'s list vars whose members spill the same way.
/datum/proc/declared_spill_list_vars()
	return null

/// Assoc: our var name -> the var on the object it names that points back
/// at us (or null). The non-owning side of an owner/child pair (REF_BACK):
/// phase 4 nulls ours and, if it still points at us, theirs.
/datum/proc/declared_back_vars()
	return null

/// Names of `src`'s vars deliberately left set after destruction (REF_KEEP):
/// exempt from the destroy postcondition (leak_check.dm).
/datum/proc/declared_keep_vars()
	return null

/// Assoc: our cache var name -> its invalidation rule, CACHE_ON_CHANGE(bits),
/// CACHE_ON_EVENT(path) or CACHE_ON_RELATION(path) (code/__DEFINES/om.dm). A
/// cache may hold object references; the object-model core nulls it when the
/// rule fires (om_cache_scan(), entity.dm), and tools/ci/declared_refs_lint.py
/// rejects an entry with no rule.
/datum/proc/declared_cache_vars()
	return null

/// Names of `src`'s vars that point at frozen definitions or registry objects
/// (REF_DEF): never deleted, so destruction leaves them alone. Read by the lint
/// and by tests; nothing at runtime needs them.
/datum/proc/declared_def_vars()
	return null

/// Names of `src`'s vars that hold round-long singletons or flyweights strongly
/// (REF_STATIC): never cleared by destruction, never reported by the leak check.
/datum/proc/declared_static_vars()
	return null

/// TRUE for a singleton / flyweight / definition type (OM_STATIC_TYPE): what a
/// handle may never point at (tools/ci/handle_kinds_lint.py).
/datum/proc/om_static_type()
	return FALSE

/// Names of a pooled type's per-use fields (REF_TRANSIENT): pool_release()
/// resets each to its initial value (code/datums/lifecycle/pool.dm).
/datum/proc/declared_transient_vars()
	return null

/// `D`'s declared_*_vars() results, cached per type on first use (see file
/// header): a type's declarations are proc-local statics, so every instance
/// of it answers identically, but they can only be *called* on a real,
/// already-constructed instance -- exactly how dq_slot_defs_for(atom/holder)
/// already caches slot_def_types() by the instance's type, not by
/// instantiating a throwaway. `.owned`, `.owned_list`, `.pair`, `.backlist`
/// -- each the list/assoc that type declared, or null.
/proc/dq_lifecycle_link_table(datum/D)
	var/static/list/cache = list()
	var/key = D.type
	var/list/table = cache[key]
	if(isnull(table))
		table = list(
			"owned" = D.declared_owned_vars(),
			"owned_list" = D.declared_owned_list_vars(),
			"owned_values" = D.declared_owned_value_vars(),
			"pair" = D.declared_pair_vars(),
			"backlist" = D.declared_backlist_vars(),
			"backlist_handle" = D.declared_backlist_handle_vars(),
			"back_handle" = D.declared_back_handle_vars(),
			"spill" = D.declared_spill_vars(),
			"spill_list" = D.declared_spill_list_vars(),
			"held" = D.declared_held_vars(),
			"back" = D.declared_back_vars(),
			"keep" = D.declared_keep_vars(),
			"static" = D.declared_static_vars(),
			"weak_list" = D.declared_weak_list_vars(),
			"back_via" = D.declared_back_via_vars(),
			"list_back" = D.declared_list_back_vars(),
			"drop" = D.declared_drop_vars(),
			"queue" = D.declared_queue_vars(),
		)
		// A declaration naming a var the type no longer has (the var was
		// removed, the REF_* line wasn't) would runtime on D.vars[name] in the
		// middle of a destroy transaction, abandoning it half done. Drop it
		// here, once per type, loudly.
		for(var/kind in table)
			var/list/names = table[kind]
			if(!length(names))
				continue
			for(var/name in names.Copy())
				var/checked = name
				if(kind == "queue" && name == LIFECYCLE_QUEUE_ALWAYS)
					continue
				if(kind == "back_via") // a path: its first hop must be ours
					var/dot = findtext(name, ".")
					if(dot)
						checked = copytext(name, 1, dot)
				if(!(checked in D.vars))
					stack_trace("LIFECYCLE: [D.type] declares [kind] var '[name]', which it doesn't have; ignoring it")
					names = names.Copy()
					names -= name
					table[kind] = names
		cache[key] = table
	return table

/// Phase 2, for a movable destroyed inside another atom: the holder's declared
/// owned, spill and held vars that name it are nulled -- a cell deleted in its
/// APC, a board in its machine -- so no child clears its holder's typed var by
/// hand.
/proc/dq_lifecycle_release_from_holder(atom/movable/AM)
	var/atom/holder = AM.loc
	if(!holder || isturf(holder) || QDELETED(holder))
		return
	var/list/table = dq_lifecycle_link_table(holder)
	var/static/list/holder_keys = list("owned", "spill", "held")
	for(var/key in holder_keys)
		for(var/var_name in table[key])
			if(holder.vars[var_name] == AM)
				holder.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link

/// Phase 3, for declared spill vars (REF_SPILL/REF_SPILL_LIST): each thing
/// still inside `AM` goes to its drop location. When that location is itself
/// being destroyed in the same batch, the thing is simply deleted with it.
/// The spill hook: a thing that lands refreshes its icon, since its sprite may
/// show the holder's state (a recharger's cell mid-charge), as a hand eject does.
/// It is the existing update_icon(), not a new base-type proc.
/proc/dq_lifecycle_spill_declared(atom/movable/AM)
	var/list/table = dq_lifecycle_link_table(AM)
	var/list/spill = table["spill"]
	var/list/spill_list = table["spill_list"]
	if(!spill && !spill_list)
		return
	var/atom/drop = AM.drop_location()
	var/doomed = !drop || QDELETED(drop)
	for(var/var_name in spill)
		var/atom/movable/thing = AM.vars[var_name]
		if(!ismovable(thing) || thing.loc != AM || QDELETED(thing))
			continue
		AM.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
		if(doomed)
			qdel(thing)
		else
			thing.forceMove(drop)
			thing.update_icon()
	// A spill list may be src's whole contents (REF_SPILL_LIST(/obj/item/clothing,
	// "contents")), which also holds its owned children: a suit's hood or a
	// voidsuit's helmet lives inside it. Those are deleted in phase 4, not spilled.
	var/list/owned_things
	if(spill_list)
		for(var/var_name in table["owned"])
			var/datum/child = AM.vars[var_name]
			if(child)
				LAZYADD(owned_things, child)
		for(var/var_name in table["owned_list"])
			var/list/children = AM.vars[var_name]
			if(islist(children))
				LAZYADD(owned_things, children)
	for(var/var_name in spill_list)
		var/list/things = AM.vars[var_name]
		if(!islist(things))
			continue
		for(var/atom/movable/thing in things.Copy())
			if(thing.loc != AM || QDELETED(thing))
				continue
			if(owned_things && (thing in owned_things))
				continue
			if(things != AM.contents)
				things -= thing
			if(doomed)
				qdel(thing)
			else
				thing.forceMove(drop)
				thing.update_icon()

/// Phase 4 (doc/rewrite/lifecycle.md §2): clears every declared relationship
/// on `D` -- owned children deleted, pair partners nulled on both sides,
/// back-list memberships removed.
/proc/dq_lifecycle_clear_links(datum/D)
	// Object-model relations, watches and forwards (code/datums/om/entity.dm).
	if(D.om_rec)
		om_teardown_links(D)
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: om teardown done")
	var/list/table = dq_lifecycle_link_table(D)
	if(!table)
		return
	// Partners found through a path, and the members of our back-lists, are told
	// first: the vars they are reached through (a REF_HELD part, an owned list) are
	// nulled or emptied below.
	if(table["back_via"] || table["list_back"])
		dq_lifecycle_clear_found_partners(D, table)
	var/list/owned = table["owned"]
	for(var/var_name in owned)
		var/datum/child = D.vars[var_name]
		D.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
		// A typed var may still hold a type path (never materialized) or a list.
		if(isdatum(child))
			dq_lifecycle_check_owner_cycle(D, var_name, child)
		// A typed var may still hold a type path (never materialized) or a list.
		// An owned child already being destroyed (two objects that own each
		// other, like an overmap mob and its marker) is only let go: its own
		// transaction is further up this stack, and qdel() on it again is the
		// "destroy proc was called multiple times" CRASH.
		if(isdatum(child) && !QDELETED(child))
			if(GLOB.dq_lifecycle_trace_depth)
				log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: deleting owned [var_name] ([child.type])")
			qdel(child)
	// Held vars (REF_HELD) are let go with their holder: the thing is deleted with the
	// holder's contents or lives on elsewhere, and a deleted holder still naming it
	// (a mob's focus on itself, an installed part) is a reference nothing would clear.
	for(var/var_name in table["held"])
		D.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: owned vars done")
	var/list/owned_list = table["owned_list"]
	for(var/var_name in owned_list)
		var/list/children = D.vars[var_name]
		if(!islist(children) || !length(children))
			continue
		var/list/copy = children.Copy()
		children.Cut()
		for(var/datum/child in copy)
			if(!QDELETED(child))
				qdel(child)
	for(var/var_name in table["weak_list"])
		var/list/weak = D.vars[var_name]
		if(islist(weak))
			weak.Cut()
	var/list/owned_values = table["owned_values"]
	for(var/var_name in owned_values)
		var/list/by_key = D.vars[var_name]
		if(!islist(by_key) || !length(by_key))
			continue
		var/list/copy = by_key.Copy()
		by_key.Cut()
		for(var/key in copy)
			var/datum/child = copy[key]
			if(isdatum(child) && !QDELETED(child))
				qdel(child)
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: owned lists done")
	for(var/our_var in table["back"])
		dq_lifecycle_clear_back(D, our_var, table["back"][our_var])
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	var/list/pairs = table["pair"]
	for(var/our_var in pairs)
		var/datum/partner = D.vars[our_var]
		if(batch && partner && batch.doomed[partner])
			// Both ends doomed: the partner's own clear drops its side.
			D.vars[our_var] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
			batch.edges_dropped++
			continue
		link_clear(D, our_var)
	var/list/backlist = table["backlist"]
	for(var/our_var in backlist)
		var/datum/owner = D.vars[our_var]
		D.vars[our_var] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
		if(batch && owner && batch.doomed[owner])
			batch.edges_dropped++
			continue // the owner's list goes with it
		if(owner && !QDELETED(owner))
			var/list_var = backlist[our_var]
			var/list/L = owner.vars[list_var]
			L?.Remove(D)
	var/list/backlist_handle = table["backlist_handle"]
	for(var/our_var in backlist_handle)
		var/datum/owner = om_resolve(D.vars[our_var])
		if(!owner || (batch && batch.doomed[owner]))
			continue
		var/list_vars = backlist_handle[our_var]
		var/h = om_handle_of(D)
		for(var/list_var in lifecycle_backlist_handle_lists(owner, list_vars))
			var/list/L = owner.vars[list_var]
			if(L)
				L.Remove(D)
				if(h)
					L.Remove(h)
	var/list/back_handle = table["back_handle"]
	for(var/our_var in back_handle)
		var/datum/partner = om_resolve(D.vars[our_var])
		if(!partner || (batch && batch.doomed[partner]))
			continue
		var/their_var = back_handle[our_var]
		if(!(their_var in partner.vars))
			continue
		var/theirs = partner.vars[their_var]
		if(theirs == D || (istext(theirs) && om_handle_is(theirs, D)))
			partner.vars[their_var] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	var/list/queues = table["queue"]
	for(var/flag in queues)
		if(flag != LIFECYCLE_QUEUE_ALWAYS && !D.vars[flag])
			continue
		var/getters = queues[flag]
		for(var/getter in (islist(getters) ? getters : list(getters)))
			var/list/Q = call(getter)()
			if(islist(Q))
				Q.Remove(D)
	for(var/var_name in table["drop"])
		D.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	for(var/var_name in table["list_back"])
		if(var_name != "contents")
			D.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link

/// Reads a REF_BACK_VIA path ("a" or "a.b.c") from `D`: each hop is a var of the
/// object reached so far, holding a reference or an OM handle. Null when a hop is
/// missing, unset or no longer resolves, or when the path leads back to `D`.
/// The result may be a /client (clients aren't datums but have vars).
/proc/lifecycle_follow_path(datum/D, path)
	var/static/list/split_paths = list()
	var/list/hops = split_paths[path]
	if(!hops)
		hops = splittext(path, ".")
		split_paths[path] = hops
	var/datum/at = D
	for(var/hop in hops)
		if(!(hop in at.vars))
			return null
		var/value = at.vars[hop]
		if(istext(value))
			value = om_resolve(value)
		if(!value || isnum(value) || ispath(value) || islist(value))
			return null
		at = value
	return at == D ? null : at

/// Takes `D` out of `partner.vars[their_var]`: removed (with its handle `h`) from a
/// list, or the var nulled when it names `D` by reference or handle.
/proc/lifecycle_unname(datum/partner, their_var, datum/D, h)
	if(!(their_var in partner.vars))
		return
	var/theirs = partner.vars[their_var]
	if(islist(theirs))
		var/list/L = theirs
		L.Remove(D)
		if(h)
			L.Remove(h)
	else if(theirs == D || (h && theirs == h))
		partner.vars[their_var] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link

/// Phase 4, REF_BACK_VIA and REF_LIST_BACK: every partner `D` reaches through a
/// declared path, and every member of `D`'s declared back-lists, stops naming it.
/proc/dq_lifecycle_clear_found_partners(datum/D, list/table)
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	var/h = om_handle_of(D)
	var/list/back_via = table["back_via"]
	for(var/path in back_via)
		var/datum/partner = lifecycle_follow_path(D, path)
		if(!partner || (batch && batch.doomed[partner]))
			continue
		for(var/their_var in lifecycle_backlist_handle_lists(partner, back_via[path]))
			lifecycle_unname(partner, their_var, D, h)
	var/list/list_back = table["list_back"]
	for(var/our_var in list_back)
		var/list/members = D.vars[our_var]
		if(!islist(members) || !length(members))
			continue
		var/member_vars = list_back[our_var]
		for(var/key in members.Copy())
			var/list/found = list(key)
			if(!isnum(key))
				var/value = members[key]
				if(value)
					found += value
			for(var/entry in found)
				var/datum/member = istext(entry) ? om_resolve(entry) : entry
				if(!member || member == D || isnum(member) || ispath(member) || islist(member))
					continue
				if(batch && batch.doomed[member])
					continue
				for(var/their_var in lifecycle_backlist_handle_lists(member, member_vars))
					lifecycle_unname(member, their_var, D, h)


/// The partner's list var names a REF_BACKLIST_HANDLE value picks for `owner`:
/// a name, a list of names, or list(/partner/type = name or names) keyed by the
/// partner's type (the first type `owner` is).
/proc/lifecycle_backlist_handle_lists(datum/owner, list_vars)
	if(!islist(list_vars))
		return list(list_vars)
	var/list/choices = list_vars
	if(length(choices) && ispath(choices[1]))
		for(var/partner_type in choices)
			if(istype(owner, partner_type))
				var/picked = choices[partner_type]
				return islist(picked) ? picked : list(picked)
		return list()
	return choices

/// Nulls whatever a declared owned/pair var still points to, without
/// deleting anything (phase 8: the owned children are already gone by now;
/// this only breaks reference cycles leftover Destroy() might have re-set).
/proc/dq_lifecycle_null_declared_refs(datum/D)
	var/list/table = dq_lifecycle_link_table(D)
	if(!table)
		return
	for(var/var_name in table["owned"])
		D.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	// A destroyed object holds nothing: held things (a datum has no contents, so
	// phase 2 never released them) and the emptied owned lists are dropped too.
	// `contents` is built in and can't be nulled.
	var/static/list/drop_keys = list("held", "owned_list", "owned_values", "drop", "list_back")
	for(var/key in drop_keys)
		for(var/var_name in table[key])
			if(var_name != "contents")
				D.vars[var_name] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	for(var/our_var in table["back"])
		dq_lifecycle_clear_back(D, our_var, table["back"][our_var])
	for(var/var_name in table["pair"])
		if(D.vars[var_name])
			link_clear(D, var_name)

/// Sets a REF_PAIR both ways: `A.vars[var_a] = B`, `B.vars[var_b] = A`,
/// clearing whatever either side pointed to first. Both types must declare
/// `var_a`/`var_b` as a matched declared_pair_vars() entry.
/proc/link_set(datum/A, var_a, datum/B, var_b)
	link_clear(A, var_a)
	link_clear(B, var_b)
	A.vars[var_a] = B // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	B.vars[var_b] = A // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link

/// Clears a REF_PAIR from `A`'s side: nulls `A.vars[var_a]`, and, if it
/// pointed somewhere, finds that object's declared reciprocal var (from its
/// own declared_pair_vars()) and nulls it too. Safe to call on an already
/// null pair.
/proc/link_clear(datum/A, var_a)
	var/datum/other = A.vars[var_a]
	A.vars[var_a] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	if(!other)
		return
	var/list/other_pairs = dq_lifecycle_link_table(other)["pair"]
	for(var/their_var in other_pairs)
		if(other.vars[their_var] == A)
			other.vars[their_var] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
			return

/// Adds `member` to `owner.vars[list_var]` and sets `member.vars[owner_var] = owner`,
/// so phase 4 removes it automatically on either side's destruction. Both
/// types must declare `owner_var` in declared_backlist_vars(): member's
/// entry is `owner_var -> list_var`.
/proc/link_backlist_add(datum/member, owner_var, datum/owner, list_var)
	member.vars[owner_var] = owner // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	var/list/L = owner.vars[list_var]
	if(!L)
		L = list()
		owner.vars[list_var] = L // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	L |= member

/// Removes `member` from the back-list side, without waiting for either
/// object's destruction.
/proc/link_backlist_remove(datum/member, owner_var)
	var/datum/owner = member.vars[owner_var]
	member.vars[owner_var] = null // ALLOW(api): REF_* link plumbing: clears/pairs the declared var named by the link
	if(!owner)
		return
	// owner_var is member's var name, not owner's -- the list var lives on
	// declared_backlist_vars() the way member declared it, which is the
	// contract: member says "my owner_var points at the list named X on my
	// owner's type". Read X from member's own declaration.
	var/list/member_backlist = dq_lifecycle_link_table(member)["backlist"]
	var/list_var = member_backlist?[owner_var]
	if(!list_var)
		return
	var/list/L = owner.vars[list_var]
	L?.Remove(member)

/// REF_PAIR/REF_BACKLIST helper: the parent type's assoc declaration plus
/// `extra`, as a new list (the parent's is a shared per-type table).
/proc/lifecycle_merge_assoc(list/parent, list/extra)
	. = parent ? parent.Copy() : list()
	for(var/key in extra)
		.[key] = extra[key]

/// REF_BACK: nulls `D.vars[our_var]` and, when `their_var` is named and the
/// object it pointed at still points back at D through it, that too.
/proc/dq_lifecycle_clear_back(datum/D, our_var, their_var)
	var/datum/other = D.vars[our_var]
	D.vars[our_var] = null
	if(!their_var || !isdatum(other) || !(their_var in other.vars))
		return
	if(other.vars[their_var] == D)
		other.vars[their_var] = null

/// While a list, lifecycle framework reports (ownership cycles, leaks) are
/// appended here instead of raised as runtimes (unit tests of the checks).
GLOBAL_VAR(dq_lifecycle_report_capture)

/// Reports a lifecycle framework violation: a stack_trace (a runtime, so a
/// test run fails), or into GLOB.dq_lifecycle_report_capture while a test
/// captures. Each distinct message is reported once per round.
/proc/dq_lifecycle_report(message)
	var/list/capture = GLOB.dq_lifecycle_report_capture
	if(islist(capture))
		capture += message
		return
	var/static/list/reported = list()
	if(reported[message])
		return
	reported[message] = TRUE
	stack_trace(message)

/// Ownership must be a tree. Called for each owned child as phase 4 lets it
/// go: if the child owns `D` back through any declared owned var, two types
/// REF_OWN each other (tools/ci/ownership_cycle_lint.py is the static half;
/// this catches untyped vars and declarations written as procs). The release
/// of an already-deleting child (above) keeps it from crashing; this makes it
/// loud. One side should own, the other name it with REF_BACK.
/proc/dq_lifecycle_check_owner_cycle(datum/D, var_name, datum/child)
	var/list/child_table = dq_lifecycle_link_table(child)
	for(var/child_var in child_table["owned"])
		if(child.vars[child_var] == D)
			dq_lifecycle_report("LIFECYCLE OWNERSHIP CYCLE: [D.type].[var_name] owns [child.type], and [child.type].[child_var] owns [D.type] back. Ownership must be a tree: make one side REF_BACK.")
			return
	for(var/child_var in child_table["owned_list"])
		var/list/L = child.vars[child_var]
		if(islist(L) && (D in L))
			dq_lifecycle_report("LIFECYCLE OWNERSHIP CYCLE: [D.type].[var_name] owns [child.type], and [child.type].[child_var] (owned list) owns [D.type] back. Ownership must be a tree: make one side REF_BACK.")
			return
