// L2: the links framework (roadmap L track, doc/rewrite/lifecycle.md ง4).
//
// Every object-typed var on a datum is declared as exactly one kind:
//   - slot content            containment (ledger.dm/lifecycle.dm) -- not this file
//   - DECLARE_REF(...) with a kind    one line per var, next to the type (code/__defines/lifecycle.dm
//                              lists the kinds: OWNED, PAIR, BACK, HELD, STATIC, ...)
//   - handle (om_handle())     resolved on read, never cleaned
//   - tmp cache                recomputable; scrubbed in phase 8
//
// Each DECLARE_REF(PATH, VAR, KIND, OPT) line is an override of declared_refs() that
// adds one entry on top of ..(), so a type's table holds its parents' entries
// too. dq_lifecycle_link_table() builds that table once per type, lazily, the
// first time it sees an instance -- the same lazy-once-per-type cache
// dq_slot_defs_for() uses, so a type nobody ever destroys never pays for one.
//
// tools/ci/declared_refs_lint.py enforces "every object-typed var is declared
// as exactly one kind" statically, and suggests a kind for an undeclared var.

/// The type's declared references: kind (a REFKIND_* key) -> assoc of var name ->
/// the kind's OPT. Built by the DECLARE_REF() lines on the type and its parents, each adding
/// one entry on top of ..(). Read it through dq_lifecycle_link_table(), which caches
/// it per type; never override it by hand.
/datum/proc/declared_refs()
	return null

/// DECLARE_REF() plumbing: `parent` (a fresh table from ..(), or null) with `kind`'s entry
/// `name` = `opt` added. A later REF for the same var and kind replaces the earlier.
/proc/lifecycle_declare_ref(list/parent, kind, name, opt)
	. = parent || list()
	var/list/entries = .[kind]
	if(!entries)
		entries = list()
		.[kind] = entries
	entries[name] = opt

/// Runs in the destroy transaction just before phase 4 (links) nulls, deletes and
/// unlinks the declared vars: the place for teardown that must still read them
/// (a holder ending its busy state, a hologram handing bellies back to its master,
/// a projectile drawing its tracers from owned beam segments). Must not sleep.
/datum/proc/lifecycle_prerelease()
	return

/// The live entities weak list `L` (DECLARE_REF(..., WEAK_LIST)) names, in order. Prunes the
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

/// Assoc: our cache var name -> its invalidation rule, CACHE_ON_CHANGE(bits),
/// CACHE_ON_EVENT(path) or CACHE_ON_RELATION(path) (code/__DEFINES/om.dm). A
/// cache may hold object references; the object-model core nulls it when the
/// rule fires (om_cache_scan(), entity.dm), and tools/ci/declared_refs_lint.py
/// rejects an entry with no rule.
/datum/proc/declared_cache_vars()
	return null

/// TRUE for a singleton / flyweight / definition type (OM_STATIC_TYPE): what a
/// handle may never point at (tools/ci/handle_kinds_lint.py).
/datum/proc/om_static_type()
	return FALSE

/// `D`'s declared_refs() table, cached per type on first use (see file header):
/// every instance of a type answers identically, but the proc can only be called
/// on a real instance -- the same way dq_slot_defs_for(atom/holder) caches
/// slot_def_types() by the instance's type. Keyed by REFKIND_* ("owned", "pair",
/// ...); each entry is an assoc of var name -> OPT, or absent.
/proc/dq_lifecycle_link_table(datum/D)
	var/static/list/cache = list()
	var/key = D.type
	var/list/table = cache[key]
	if(isnull(table))
		table = D.declared_refs() || list()
		// A declaration naming a var the type no longer has (the var was
		// removed, the DECLARE_REF line wasn't) would runtime on D.vars[name] in the
		// middle of a destroy transaction, abandoning it half done. Drop it
		// here, once per type, loudly.
		// DEF/STATIC/TRANSIENT entries are only read by the lints and pool.dm.
		var/static/list/unchecked = list(REFKIND_DEF = TRUE, REFKIND_STATIC = TRUE, REFKIND_TRANSIENT = TRUE)
		for(var/kind in table)
			var/list/names = table[kind]
			if(!length(names) || unchecked[kind])
				continue
			for(var/name in names.Copy())
				var/checked = name
				if(kind == REFKIND_QUEUE && name == LIFECYCLE_QUEUE_ALWAYS)
					continue
				if(kind == REFKIND_BACK_VIA) // a path: its first hop must be ours
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
				holder.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link

/// Phase 3, for declared spill vars (DECLARE_REF(..., SPILL)/DECLARE_REF(..., SPILL_LIST)): each thing
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
		AM.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
		if(doomed)
			qdel(thing)
		else
			thing.forceMove(drop)
			thing.update_icon()
	// A spill list may be src's whole contents (DECLARE_REF(/obj/item/clothing,
	// "contents", SPILL_LIST, null)), which also holds its owned children: a suit's hood or a
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

/// Phase 4 (doc/rewrite/lifecycle.md ยง2): clears every declared relationship
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
	// first: the vars they are reached through (a DECLARE_REF(..., HELD) part, an owned list) are
	// nulled or emptied below.
	if(table["back_via"] || table["list_back"])
		dq_lifecycle_clear_found_partners(D, table)
	var/list/owned = table["owned"]
	for(var/var_name in owned)
		var/datum/child = D.vars[var_name]
		D.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
		// A typed var may still hold a type path (never materialized) or a list.
		if(isdatum(child))
			dq_lifecycle_check_owner_cycle(D, var_name, child)
		// An owned child already being destroyed (two objects that own each
		// other, like an overmap mob and its marker) is only let go: its own
		// transaction is further up this stack, and qdel() on it again is the
		// "destroy proc was called multiple times" CRASH.
		if(isdatum(child) && !QDELETED(child))
			if(GLOB.dq_lifecycle_trace_depth)
				log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] links: deleting owned [var_name] ([child.type])")
			qdel(child)
	// Held vars (DECLARE_REF(..., HELD)) are let go with their holder: the thing is deleted with the
	// holder's contents or lives on elsewhere, and a deleted holder still naming it
	// (a mob's focus on itself, an installed part) is a reference nothing would clear.
	for(var/var_name in table["held"])
		D.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
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
			D.vars[our_var] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
			batch.edges_dropped++
			continue
		link_clear(D, our_var)
	var/list/backlist = table["backlist"]
	for(var/our_var in backlist)
		var/datum/owner = D.vars[our_var]
		D.vars[our_var] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
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
			partner.vars[their_var] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
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
		D.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	for(var/var_name in table["list_back"])
		if(var_name != "contents")
			D.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link

/// Reads a DECLARE_REF(..., BACK_VIA) path ("a" or "a.b.c") from `D`: each hop is a var of the
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
		partner.vars[their_var] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link

/// Phase 4, DECLARE_REF(..., BACK_VIA) and DECLARE_REF(..., LIST_BACK): every partner `D` reaches through a
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


/// The partner's list var names a DECLARE_REF(..., BACKLIST_HANDLE) value picks for `owner`:
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
		D.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	// A destroyed object holds nothing: held things (a datum has no contents, so
	// phase 2 never released them) and the emptied owned lists are dropped too.
	// `contents` is built in and can't be nulled.
	var/static/list/drop_keys = list("held", "owned_list", "owned_values", "drop", "list_back")
	for(var/key in drop_keys)
		for(var/var_name in table[key])
			if(var_name != "contents")
				D.vars[var_name] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	for(var/our_var in table["back"])
		dq_lifecycle_clear_back(D, our_var, table["back"][our_var])
	for(var/var_name in table["pair"])
		if(D.vars[var_name])
			link_clear(D, var_name)

/// Sets a DECLARE_REF(..., PAIR) both ways: `A.vars[var_a] = B`, `B.vars[var_b] = A`,
/// clearing whatever either side pointed to first. Both types must declare
/// `var_a`/`var_b` as a matched DECLARE_REF(..., PAIR, ...) entry.
/proc/link_set(datum/A, var_a, datum/B, var_b)
	link_clear(A, var_a)
	link_clear(B, var_b)
	A.vars[var_a] = B // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	B.vars[var_b] = A // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link

/// Clears a DECLARE_REF(..., PAIR) from `A`'s side: nulls `A.vars[var_a]`, and, if it
/// pointed somewhere, finds that object's declared reciprocal var (from its
/// own PAIR declarations) and nulls it too. Safe to call on an already
/// null pair.
/proc/link_clear(datum/A, var_a)
	var/datum/other = A.vars[var_a]
	A.vars[var_a] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	if(!other)
		return
	var/list/other_pairs = dq_lifecycle_link_table(other)[REFKIND_PAIR]
	for(var/their_var in other_pairs)
		if(other.vars[their_var] == A)
			other.vars[their_var] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
			return

/// Adds `member` to `owner.vars[list_var]` and sets `member.vars[owner_var] = owner`,
/// so phase 4 removes it automatically on either side's destruction. Both
/// types must declare it: member's DECLARE_REF(..., owner_var, BACKLIST, list_var).
/proc/link_backlist_add(datum/member, owner_var, datum/owner, list_var)
	member.vars[owner_var] = owner // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	var/list/L = owner.vars[list_var]
	if(!L)
		L = list()
		owner.vars[list_var] = L // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	L |= member

/// Removes `member` from the back-list side, without waiting for either
/// object's destruction.
/proc/link_backlist_remove(datum/member, owner_var)
	var/datum/owner = member.vars[owner_var]
	member.vars[owner_var] = null // ALLOW(api): DECLARE_REF link plumbing: clears/pairs the declared var named by the link
	if(!owner)
		return
	// owner_var is member's var name, not owner's -- the list var lives on
	// member's BACKLIST declaration, the way member declared it, which is the
	// contract: member says "my owner_var points at the list named X on my
	// owner's type". Read X from member's own declaration.
	var/list/member_backlist = dq_lifecycle_link_table(member)[REFKIND_BACKLIST]
	var/list_var = member_backlist?[owner_var]
	if(!list_var)
		return
	var/list/L = owner.vars[list_var]
	L?.Remove(member)

/// DECLARE_REF(..., BACK): nulls `D.vars[our_var]` and, when `their_var` is named and the
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
/// DECLARE_REF(..., OWNED) each other (tools/ci/ownership_cycle_lint.py is the static half;
/// this catches untyped vars and declarations written as procs). The release
/// of an already-deleting child (above) keeps it from crashing; this makes it
/// loud. One side should own, the other name it with DECLARE_REF(..., BACK).
/proc/dq_lifecycle_check_owner_cycle(datum/D, var_name, datum/child)
	var/list/child_table = dq_lifecycle_link_table(child)
	for(var/child_var in child_table["owned"])
		if(child.vars[child_var] == D)
			dq_lifecycle_report("LIFECYCLE OWNERSHIP CYCLE: [D.type].[var_name] owns [child.type], and [child.type].[child_var] owns [D.type] back. Ownership must be a tree: make one side DECLARE_REF(..., BACK).")
			return
	for(var/child_var in child_table["owned_list"])
		var/list/L = child.vars[child_var]
		if(islist(L) && (D in L))
			dq_lifecycle_report("LIFECYCLE OWNERSHIP CYCLE: [D.type].[var_name] owns [child.type], and [child.type].[child_var] (owned list) owns [D.type] back. Ownership must be a tree: make one side DECLARE_REF(..., BACK).")
			return
