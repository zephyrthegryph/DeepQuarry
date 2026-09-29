// Ownership tables (doc/rewrite/ownership.md): one per type, built from the type's
// declare_ownership() override the first time an instance asks, cached in the `own_table` shared
// cache.

// ---------------------------------------------------------------- declaring

/// The type's ownership declarations: the one well-known proc a type overrides to declare the
/// exceptions to kind inference. Call ..() first, then one concept proc per var:
///
///	/obj/machinery/sleeper/declare_ownership(decl)
///		..()
///		own(decl, nameof(beaker), policy = OWN_SPILL)
///		rel(decl, nameof(console), pair = nameof(/obj/machinery/sleep_console::sleeper))
///
/// Runs once per type (on the first instance that needs the table); never call it by hand.
/datum/proc/declare_ownership(datum/own_decls/decl)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// OWN_TIMER names: the timers this type owns (code/datums/om/timer.dm).
/datum/proc/declared_timer_slots()
	return list()

/// The declarations collected from one type's declare_ownership() chain.
/datum/own_decls
	/// var name -> entry list(kind, arg, partner, extra, is_list, watch)
	var/list/entries = list()
	/// "var: ..." lines for a var declared with two kinds across the hierarchy.
	var/list/conflicts
	/// Annotations: keep_after_destroy / pool_reset / forward var names.
	var/list/keep
	var/list/pool_reset
	var/list/forward
	/// rel(decl, keyed = nameof(key)) with no var: instances are keyed targets found through `key`.
	var/keyed_key

/// Records `entry` for `var_name`. One kind per var across the hierarchy: a subtype may change an
/// own policy or a relation's options, never the kind. A conflict is reported when the table is
/// built.
/datum/own_decls/proc/put(var_name, list/entry)
	var/list/old = entries[var_name]
	if(old && old[OWNE_KIND] != entry[OWNE_KIND])
		LAZYADD(conflicts, "[var_name]: declared [own_kind_name(old[OWNE_KIND])] by an ancestor and [own_kind_name(entry[OWNE_KIND])] here")
	entries[var_name] = entry

/// The annotation options every concept proc takes.
/datum/own_decls/proc/annotate(var_name, keep_after_destroy, pool_reset, forward)
	if(keep_after_destroy)
		LAZYOR(keep, var_name)
	if(pool_reset)
		LAZYOR(src.pool_reset, var_name)
	if(forward)
		LAZYOR(src.forward, var_name)

/**
 * Own: the holder owns var_name's value(s) (one, a list, or assoc values) and tears them down.
 *
 * - `policy`: OWN_DELETE (destroyed with the holder), OWN_SPILL (a movable drops to the holder's
 *   drop location) or OWN_CONTAINED (a movable in the holder's contents; its ledger slot decides).
 * - `policy_proc`: PROC_REF(name) / TYPE_PROC_REF(type, name) of a holder proc returning the policy at
 *   teardown (instead of `policy`).
 * - `if_var` / `else_policy`: `policy` while the holder's var `if_var` (a nameof()) is true, else
 *   `else_policy`.
 * - Annotations: `keep_after_destroy` (the leak check skips the var), `pool_reset`
 *   (pool_release() resets it to its initial value), `forward` (replace_with() carries it to the
 *   successor: an owned value moves, a relation re-links, anything else is copied).
 *
 * With no policy, policy_proc or if_var the call only annotates: the var keeps the kind its writes
 * give it (none, for plain data such as a pooled packet's numbers).
 */
/proc/own(datum/own_decls/decl, var_name, policy = null, policy_proc = null, if_var = null, else_policy = null, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE)
	decl.annotate(var_name, keep_after_destroy, pool_reset, forward)
	if(policy_proc)
		decl.put(var_name, list(OWNK_OWN, policy_proc, null, null, FALSE, null))
	else if(if_var)
		decl.put(var_name, list(OWNK_OWN, isnull(policy) ? OWN_DELETE : policy, if_var, isnull(else_policy) ? OWN_DELETE : else_policy, FALSE, null))
	else if(!isnull(policy))
		decl.put(var_name, list(OWNK_OWN, policy, null, null, FALSE, null))

/// Shared: var_name holds a registered singleton or DEF (only an untyped var needs this; a var
/// typed as a registry type is implicitly shared). Never cleared.
/proc/shared(datum/own_decls/decl, var_name, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE)
	decl.annotate(var_name, keep_after_destroy, pool_reset, forward)
	decl.put(var_name, list(OWNK_SHARED, null, null, null, FALSE, null))

/// Proto: var_name holds a registered prototype or a private copy the holder owns
/// (proto_private / proto_set). Teardown deletes private copies only.
/proc/proto(datum/own_decls/decl, var_name, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE)
	decl.annotate(var_name, keep_after_destroy, pool_reset, forward)
	decl.put(var_name, list(OWNK_PROTO, null, null, null, FALSE, null))

/**
 * Relation: var_name is a non-owning view the framework clears when the target dies.
 *
 * - `list`: the view is a list (1:N, or the "many" side of a pair).
 * - `pair`: two-sided. `nameof(/partner/type::partner_var)`, the partner's var naming us back
 *   (single or a list; the partner declares its end too). One rel_set()/rel_add() writes both
 *   sides; a single end is exclusive. Never write the partner's side by hand.
 * - `symmetric`: symmetric membership. var_name is a list; linking A to B adds each to the other's
 *   var_name.
 * - `keyed` + `keyed_target`: auto-linked by id. When the holder or a `keyed_target` instance
 *   materializes, the view links to the targets whose key equals the holder's var `keyed`.
 * - `keyed` alone, with no var_name: instances of this type are keyed targets, found by keyed
 *   relations through their var `keyed`.
 * - `watch`: list(nameof(/target/type::var), ...), the target vars the holder's reactive procs
 *   (draw, should_run, hidden_verbs, ui_data, needs procs) read. While linked, a changed() of the
 *   target marks the holder changed too.
 */
/proc/rel(datum/own_decls/decl, var_name = null, list = FALSE, pair = null, symmetric = FALSE, keyed = null, keyed_target = null, list/watch = null, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE)
	if(isnull(var_name))
		if(!keyed || keyed_target)
			CRASH("rel() without a var declares a keyed target: pass keyed = nameof(key) only")
		decl.keyed_key = keyed
		return
	decl.annotate(var_name, keep_after_destroy, pool_reset, forward)
	var/shape = RELS_PLAIN
	var/partner = null
	if(symmetric)
		shape = RELS_SYMMETRIC
		partner = var_name
		list = TRUE
	else if(pair)
		shape = RELS_PAIR
		partner = pair
	var/extra = null
	if(keyed_target)
		if(!keyed)
			CRASH("rel([var_name]): keyed_target needs keyed = nameof(our key var)")
		extra = list(keyed_target, keyed)
	decl.put(var_name, list(OWNK_REL, shape, partner, extra, !!list, length(watch) ? watch.Copy() : null))

/proc/own_kind_name(kind)
	switch(kind)
		if(OWNK_OWN)
			return "OWN"
		if(OWNK_SHARED)
			return "SHARED"
		if(OWNK_PROTO)
			return "PROTO"
		if(OWNK_REL)
			return "REL"
	return "?[kind]"

/// One type's ownership table. Read-only after build.
/datum/own_table
	var/owner_type
	/// var name -> entry
	var/list/entries
	/// Var names by kind, in declaration order.
	var/list/own_vars
	var/list/ref_vars
	var/list/proto_vars
	var/list/shared_vars
	/// Keyed relation var names.
	var/list/keyed_vars
	/// keep_after_destroy / pool_reset names.
	var/list/keep_vars
	var/list/pool_reset_vars
	/// OWN_TIMER names (owned timers), or null.
	var/list/timer_slots
	/// TRUE when the type declares nothing to tear down (the fast path).
	var/empty = TRUE
	/// TRUE when materialize/dematerialize has keyed-link work (keyed views, or a keyed target).
	var/materialize_work = FALSE
	/// forward-annotated var names (om_forward_state()), or null.
	var/list/forward_vars
	/// The key var when instances are keyed targets (rel(decl, keyed = ...)), or null.
	var/keyed_key
	/// REL vars declared with watch =, or null.
	var/list/watch_vars

/// D's ownership table (never null).
/proc/own_table_of(datum/D)
	RETURN_TYPE(/datum/own_table)
	// The release fast path in every build: this runs several times per atom at boot (~850k calls
	// on Southern Cross), and the test-build guard only verifies list values (a table is a datum)
	// and keys that are not type paths (this one always is).
	return _CACHED_KEY_FAST(own_table, D.type, D)

DECLARE_SHARED_CACHE(own_table, GLOBAL_PROC_REF(build_own_table), SC_NEVER)

/proc/build_own_table(datum/D)
	var/datum/own_table/T = new
	T.owner_type = D.type
	var/datum/own_decls/decl = new
	D.declare_ownership(decl)
	for(var/line in decl.conflicts)
		OWN_REPORT("[D.type]: one kind per var: [line]")
	T.entries = decl.entries
	for(var/var_name in T.entries)
		var/list/entry = T.entries[var_name]
		if(!(var_name in D.vars))
			OWN_REPORT("[D.type] declares [own_kind_name(entry[OWNE_KIND])] var '[var_name]', which it doesn't have")
			continue
		switch(entry[OWNE_KIND])
			if(OWNK_OWN)
				LAZYADD(T.own_vars, var_name)
			if(OWNK_REL)
				LAZYADD(T.ref_vars, var_name)
				if(entry[OWNE_EXTRA])
					LAZYADD(T.keyed_vars, var_name)
				if(entry[OWNE_WATCH])
					LAZYADD(T.watch_vars, var_name)
			if(OWNK_PROTO)
				LAZYADD(T.proto_vars, var_name)
			if(OWNK_SHARED)
				LAZYADD(T.shared_vars, var_name)
	T.keep_vars = decl.keep
	T.pool_reset_vars = decl.pool_reset
	T.forward_vars = decl.forward
	T.keyed_key = decl.keyed_key
	if(T.keyed_key && !(T.keyed_key in D.vars))
		OWN_REPORT("[D.type] is a keyed target through var '[T.keyed_key]', which it doesn't have")
	var/list/slots = D.declared_timer_slots()
	T.timer_slots = length(slots) ? slots : null
	T.empty = !(T.own_vars || T.ref_vars || T.proto_vars)
	T.materialize_work = !!(T.keyed_vars || T.keyed_key)
	own_validate_table(D, T)
	return T

/// The kind x value matrix, per built table (boot and first use): the checks that need an
/// instance. The static half (declared var types) is tools/ci/ownership_lint.py.
/proc/own_validate_table(datum/D, datum/own_table/T)
	for(var/var_name in T.entries)
		if(!(var_name in D.vars))
			continue
		var/list/entry = T.entries[var_name]
		var/value = D.vars[var_name]
		switch(entry[OWNE_KIND])
			if(OWNK_OWN)
				var/policy = entry[OWNE_ARG]
				var/by_proc = istext(policy) || ispath(policy)
				if(!by_proc && !(policy in list(OWN_DELETE, OWN_SPILL, OWN_CONTAINED)))
					OWN_REPORT("[D.type].[var_name]: unknown teardown policy [policy]")
				if(by_proc && !hascall(D, own_proc_name(policy)))
					OWN_REPORT("[D.type].[var_name]: policy proc [policy] is not a proc of [D.type]")
				if(policy == OWN_CONTAINED && !ismovable(D) && !isturf(D))
					OWN_REPORT("[D.type].[var_name]: CONTAINED on a type with no contents")
				if(entry[OWNE_PARTNER] && !(entry[OWNE_PARTNER] in D.vars))
					OWN_REPORT("[D.type].[var_name]: own() if_var [entry[OWNE_PARTNER]] is not a var")
				var/datum/held = value
				if(isdatum(held) && is_registered(held))
					OWN_REPORT("[D.type].[var_name]: OWN of registry type [held.type] (a registered instance is SHARED; a per-holder copy is PROTO)")
			if(OWNK_REL)
				if(entry[OWNE_ARG] == RELS_SYMMETRIC && !islist(value) && !isnull(value))
					OWN_REPORT("[D.type].[var_name]: rel(symmetric = TRUE) needs a list var")

/// A framework write changed holder.var_name. When the var is also a declared OM field
/// (OM_FIELD), its channel is raised exactly as the field's setter would, so stages, watches and
/// while-declarations gated on it see the change (a relation view cleared because its target died,
/// an owned child disposed of, a proto swapped). Before the OM registry exists nothing listens.
/proc/own_field_changed(datum/holder, var_name)
	var/datum/om/registry/R = GLOB?.om_reg
	if(!R || !holder)
		return
	var/list/fields = R.fields_by_type[holder.type] || R.fields_of(holder.type)
	var/channel = fields[var_name]
	if(channel)
		om_changed(holder, channel)

/// The bare name of a proc path (/obj/foo/proc/bar -> "bar").
/proc/own_proc_name(proc_path)
	var/text = "[proc_path]"
	var/slash = findlasttext(text, "/")
	return slash ? copytext(text, slash + 1) : text

/// The declaration entry for `var_name` on `holder`, or null.
/proc/own_entry(datum/holder, var_name)
	return own_table_of(holder).entries[var_name]

/// The entry for holder.var_name, which must be of `kind`. An undeclared var is learned: the
/// first own_set()/own_add() on it records an implicit own(policy = OWN_DELETE), the first
/// rel_set()/rel_add() an implicit rel(), in the type's table (ownership.md §7: declarations are only for exceptions).
/// A var of another kind is reported and null is returned.
/proc/own_entry_of_kind(datum/holder, var_name, kind, is_list = FALSE)
	var/datum/own_table/T = own_table_of(holder)
	var/list/entry = T.entries[var_name]
	if(!entry)
		if(!(var_name in holder.vars))
			OWN_REPORT("[holder.type] has no var '[var_name]'")
			return null
		switch(kind)
			if(OWNK_OWN)
				entry = list(OWNK_OWN, OWN_DELETE, null, null, is_list, null)
				LAZYADD(T.own_vars, var_name)
			if(OWNK_REL)
				entry = list(OWNK_REL, RELS_PLAIN, null, null, is_list, null)
				LAZYADD(T.ref_vars, var_name)
			else
				OWN_REPORT("[holder.type].[var_name] is not declared [own_kind_name(kind)]")
				return null
		T.entries[var_name] = entry
		T.empty = FALSE
		return entry
	if(entry[OWNE_KIND] != kind)
		OWN_REPORT("[holder.type].[var_name] is [own_kind_name(entry[OWNE_KIND])], not [own_kind_name(kind)]")
		return null
	return entry

/// Boot validation (doc/rewrite/ownership.md sec 8): builds the ownership table of every atom type
/// present in the world after map load, and of every registered datum's type, so a declaration
/// conflict (two kinds for one var across the hierarchy, a missing var, a bad policy) is reported
/// at boot rather than on first use. The static half is tools/ci/ownership_lint.py. Returns the
/// number of types checked.
/proc/own_validate_boot()
	var/list/seen = list()
	for(var/atom/A in world)
		if(seen[A.type])
			continue
		seen[A.type] = TRUE
		own_table_of(A)
		CHECK_TICK
	for(var/enum_proc in GLOB.registry_enum_procs)
		var/list/instances = call(enum_proc)()
		for(var/key in instances)
			var/datum/D = isdatum(key) ? key : instances[key]
			if(isdatum(D) && !seen[D.type])
				seen[D.type] = TRUE
				own_table_of(D)
	log_world("OWNERSHIP: validated the tables of [length(seen)] types at boot")
	return length(seen)

