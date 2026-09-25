// L2: the links framework (roadmap L track, doc/rewrite/lifecycle.md §4).
//
// Every object-typed var on a datum is declared as exactly one kind:
//   - slot content            containment (ledger.dm/lifecycle.dm) -- not this file
//   - REF_OWNED / REF_OWNED_LIST   a child that isn't contained, deleted in phase 4
//   - REF_PAIR                 two-sided; link_set()/link_clear() keep both sides in sync
//   - REF_BACKLIST             membership in another object's list, removed automatically
//   - weak (datum/weakref)     the default for everything else -- resolved on read, never cleaned
//   - tmp cache                recomputable; scrubbed in phase 8
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
			"pair" = D.declared_pair_vars(),
			"backlist" = D.declared_backlist_vars(),
		)
		cache[key] = table
	return table

/// Phase 4 (doc/rewrite/lifecycle.md §2): clears every declared relationship
/// on `D` -- owned children deleted, pair partners nulled on both sides,
/// back-list memberships removed.
/proc/dq_lifecycle_clear_links(datum/D)
	// Object-model relations, watches and forwards (code/datums/om/entity.dm).
	if(D.om_rec)
		om_teardown_links(D)
	var/list/table = dq_lifecycle_link_table(D)
	if(!table)
		return
	var/list/owned = table["owned"]
	for(var/var_name in owned)
		var/datum/child = D.vars[var_name]
		D.vars[var_name] = null
		if(child)
			qdel(child)
	var/list/owned_list = table["owned_list"]
	for(var/var_name in owned_list)
		var/list/children = D.vars[var_name]
		if(!length(children))
			continue
		var/list/copy = children.Copy()
		children.Cut()
		for(var/datum/child as anything in copy)
			qdel(child)
	var/list/pairs = table["pair"]
	for(var/our_var in pairs)
		link_clear(D, our_var)
	var/list/backlist = table["backlist"]
	for(var/our_var in backlist)
		var/datum/owner = D.vars[our_var]
		D.vars[our_var] = null
		if(owner && !QDELETED(owner))
			var/list_var = backlist[our_var]
			var/list/L = owner.vars[list_var]
			L?.Remove(D)

/// Nulls whatever a declared owned/pair var still points to, without
/// deleting anything (phase 8: the owned children are already gone by now;
/// this only breaks reference cycles leftover Destroy() might have re-set).
/proc/dq_lifecycle_null_declared_refs(datum/D)
	var/list/table = dq_lifecycle_link_table(D)
	if(!table)
		return
	for(var/var_name in table["owned"])
		D.vars[var_name] = null
	for(var/var_name in table["pair"])
		if(D.vars[var_name])
			link_clear(D, var_name)

/// Sets a REF_PAIR both ways: `A.vars[var_a] = B`, `B.vars[var_b] = A`,
/// clearing whatever either side pointed to first. Both types must declare
/// `var_a`/`var_b` as a matched declared_pair_vars() entry.
/proc/link_set(datum/A, var_a, datum/B, var_b)
	link_clear(A, var_a)
	link_clear(B, var_b)
	A.vars[var_a] = B
	B.vars[var_b] = A

/// Clears a REF_PAIR from `A`'s side: nulls `A.vars[var_a]`, and, if it
/// pointed somewhere, finds that object's declared reciprocal var (from its
/// own declared_pair_vars()) and nulls it too. Safe to call on an already
/// null pair.
/proc/link_clear(datum/A, var_a)
	var/datum/other = A.vars[var_a]
	A.vars[var_a] = null
	if(!other)
		return
	var/list/other_pairs = dq_lifecycle_link_table(other)["pair"]
	for(var/their_var in other_pairs)
		if(other.vars[their_var] == A)
			other.vars[their_var] = null
			return

/// Adds `member` to `owner.vars[list_var]` and sets `member.vars[owner_var] = owner`,
/// so phase 4 removes it automatically on either side's destruction. Both
/// types must declare `owner_var` in declared_backlist_vars(): member's
/// entry is `owner_var -> list_var`.
/proc/link_backlist_add(datum/member, owner_var, datum/owner, list_var)
	member.vars[owner_var] = owner
	var/list/L = owner.vars[list_var]
	if(!L)
		L = list()
		owner.vars[list_var] = L
	L |= member

/// Removes `member` from the back-list side, without waiting for either
/// object's destruction.
/proc/link_backlist_remove(datum/member, owner_var)
	var/datum/owner = member.vars[owner_var]
	member.vars[owner_var] = null
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
