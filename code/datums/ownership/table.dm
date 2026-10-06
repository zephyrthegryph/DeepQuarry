// Ownership tables (doc/rewrite/ownership.md): one per type, built from the type's ownership() and
// relations() lists the first time an instance asks, cached in the `own_table` shared cache.

// ---------------------------------------------------------------- declaring

/**
 * The type's ownership declarations: what it owns (owns()), holds shared (shares()) or as a
 * prototype (proto()). Declare only the exceptions to kind inference (ownership.md §7).
 *
 *	/obj/machinery/sleeper/ownership()
 *		. = ..()
 *		. += owns(nameof(beaker), policy = OWN_SPILL)
 *
 * Built once per type (type_list()): the body must not read instance vars.
 */
/datum/proc/ownership()
	SHOULD_NOT_SLEEP(TRUE)
	RETURN_TYPE(/list)
	return list()

/**
 * The type's relation declarations: non-owning links the framework keeps consistent and clears
 * when either end dies (rel_one(), rel_many(), rel_key()).
 *
 *	/obj/machinery/sleeper/relations()
 *		. = ..()
 *		. += rel_one(nameof(console), back = nameof(/obj/machinery/sleep_console::sleeper))
 *
 * Built once per type (type_list()): the body must not read instance vars.
 */
/datum/proc/relations()
	SHOULD_NOT_SLEEP(TRUE)
	RETURN_TYPE(/list)
	return list()

/// The (successor var, successor's var) of an OWN_HAND_OVER entry, or null: only an entry that declares one carries the tenth slot.
/proc/own_entry_successor(list/entry)
	return length(entry) >= OWNE_TO ? entry[OWNE_TO] : null

/// One declaration entry, made by owns()/shares()/proto()/rel_one()/rel_many()/rel_key(). Shared
/// per type (never write one after it is returned).
/datum/own_entry
	/// The declared var (null for rel_key()).
	var/var_name
	/// The table entry list(kind, arg, partner, extra, is_list, watch, other_deleted, on_unlink), or
	/// null for an annotation-only entry.
	var/list/entry
	var/keep_after_destroy = FALSE
	var/pool_reset = FALSE
	var/forward = FALSE
	/// rel_key(): instances are keyed targets found through this var.
	var/keyed_key
	/// The starting occupant (owns()/rel_one()/rel_many(starts =)): a type path, a list of paths (or
	/// list(path = count)) for a list var, or the name of a var holding either. Null: none.
	var/starts

/// Interned: an identical declaration made anywhere in the tree (an ancestor's relations() that every
/// subtype's per-type list repeats, such as /atom's light_sources and heat_watches) is ONE datum and one
/// entry list, not one per type. Entries are read-only after they are returned, so sharing them is safe.
/proc/_own_entry(var_name, list/entry, keep_after_destroy, pool_reset, forward, starts)
	var/static/list/interned = list()
	var/list/parts = list("[var_name]", "[!!keep_after_destroy][!!pool_reset][!!forward]", starts_signature(starts))
	for(var/value in entry) // flat: numbers, text, paths, null, and flat lists (extra, watch)
		parts += islist(value) ? "\[[jointext(value, ",")]\]" : "[value]"
	// A list of starting occupants (list(path = count)) is not keyed here: such an entry is never shared.
	var/key = islist(starts) ? null : jointext(parts, "|")
	var/datum/own_entry/E = key && interned[key]
	if(E)
		return E
	E = new
	E.var_name = var_name
	E.entry = entry
	E.keep_after_destroy = !!keep_after_destroy
	E.pool_reset = !!pool_reset
	E.forward = !!forward
	E.starts = starts
	if(key)
		interned[key] = E
	return E

/// no_starts(nameof(v)): an annotation-only entry that cancels the starting occupant an ancestor declared for `v`; the ancestor's policy for the var is
/// unchanged. `owns(v, starts = STARTS_NONE)` does the same while restating a policy.
/proc/no_starts(var_name)
	return _own_entry(var_name, null, FALSE, FALSE, FALSE, STARTS_NONE)

/**
 * Owns: the holder owns var_name's value(s) (one, a list, or assoc values) and tears them down.
 *
 * - `policy`: OWN_DELETE (the default: destroyed with the holder), OWN_SPILL (a movable drops to
 *   the holder's drop location), OWN_CONTAINED (a movable in the holder's contents; its ledger slot
 *   decides) or OWN_KEEP (released, left alone: the value outlives the holder).
 *   `policy = OWN_NONE` with only annotations declares no kind (plain data a pool resets).
 * - `policy_proc`: PROC_REF(name) / TYPE_PROC_REF(type, name) of a holder proc returning the policy
 *   at teardown (instead of `policy`).
 * - `if_var` / `else_policy`: `policy` while the holder's var `if_var` (a nameof()) is true, else
 *   `else_policy`.
 * - `successor` / `successor_var`: where OWN_HAND_OVER sends the value: `successor` (a nameof()) is the holder's var that names the successor, `successor_var` (a nameof()) the
 *   successor's var that takes it. `owns(nameof(cell), policy = OWN_HAND_OVER, successor = nameof(wreck), successor_var = nameof(wreck.crowbar_salvage))`; with if_var the hand-over
 *   is conditional (`if_var = nameof(wrecked)`, `else_policy = OWN_DELETE`). A successor that was never made (the var is empty) means the value is deleted.
 * - Annotations: `keep_after_destroy` (the leak check skips the var), `pool_reset`
 *   (pool_release() resets it to its initial value), `forward` (replace_with() carries it to the
 *   successor: an owned value moves, a relation re-links, anything else is copied).
 * - `is_list`: the var is a list (owns_many); own_move()/own_transfer() then add to it even while it is null.
 * - `starts`: the starting occupant, made at init (own_init_starts()): a type path, a list of paths or
 *   list(path = count) for a list var, or nameof() a var holding either (`starts = nameof(cell_type)`,
 *   so a map or subtype override of that var picks the type). The var itself wins: a mapped path in it
 *   is made instead, an instance in it makes nothing. A PROC_REF decides everything: it is called with the var's current value and
 *   returns what the var starts with (a type, a list of types, instances it made, or key = instance for an associative owns_many).
 */
/proc/owns(var_name, policy = OWN_DELETE, policy_proc = null, if_var = null, else_policy = OWN_DELETE, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE, type = null, starts = null, is_list = FALSE, successor = null, successor_var = null)
	if(policy == OWN_PRIVATE_COPY)
		if(!isnull(starts))
			CRASH("owns([var_name]): OWN_PRIVATE_COPY holds a prototype or a private copy of one; it has no starting occupant")
		return proto(var_name, keep_after_destroy, pool_reset, forward)
	var/list/entry = null
	if(policy_proc)
		entry = list(OWNK_OWN, policy_proc, null, null, FALSE, null, CLEAR, null, null)
	else if(if_var)
		entry = list(OWNK_OWN, isnull(policy) ? OWN_DELETE : policy, if_var, isnull(else_policy) ? OWN_DELETE : else_policy, FALSE, null, CLEAR, null, null)
	else if(policy == OWN_NONE && !isnull(starts))
		CRASH("owns([var_name]): a starting occupant needs a kind (owns_one / owns_many), not policy = OWN_NONE")
	else if(policy != OWN_NONE)
		entry = list(OWNK_OWN, policy, null, null, FALSE, null, CLEAR, null, null)
	if(entry && type)
		entry[OWNE_TYPE] = type
	if(entry && (successor || successor_var))
		if(!successor || !successor_var)
			CRASH("owns([var_name]): successor = and successor_var = go together (the holder's var naming the successor, and the successor's var that takes the value)")
		entry.len = OWNE_TO // the tenth slot is only there for an entry that hands over (own_entry_successor())
		entry[OWNE_TO] = list(successor, successor_var)
	if(entry && is_list) // owns_many: own_move()/own_transfer() add to a list that is still null instead of storing the value as a scalar
		entry[OWNE_LIST] = TRUE
	return _own_entry(var_name, entry, keep_after_destroy, pool_reset, forward, starts)

// There is no shares(): a var holding a registered singleton, a DEF or another flyweight is declared by its type
// (`var/datum/sys_periodic_def/while_def`). A registry type (REGISTRY_TYPE) or a flyweight type (flyweight_types(),
// ownership/flyweight.dm) needs no declaration: the ownership lint and the destroy leak check skip it.

/// The OWN_PRIVATE_COPY entry (rel_one/owns(policy = OWN_PRIVATE_COPY)): var_name holds a registered prototype or a
/// private copy the holder owns (proto_private / proto_set). Teardown deletes private copies only. Internal: write
/// `rel_one(nameof(v), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)`.
/proc/proto(var_name, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE)
	return _own_entry(var_name, list(OWNK_PROTO, null, null, null, FALSE, null, CLEAR, null, null), keep_after_destroy, pool_reset, forward)

/**
 * A single relation view: var_name names at most one entity, cleared when it dies.
 *
 * - `back`: two-sided. `nameof(/other/type::var)`, the other end's var naming us back (single or
 *   a list; the other type declares its end too). One rel_link() writes both sides; a single end is
 *   exclusive (linking a new partner unlinks the old one on both sides). Never write the other side.
 * - `other_deleted`: CLEAR (the default: the view drops it) or DELETE_ME (the holder is deleted too).
 * - `on_unlink`: PROC_REF(x), a holder proc called as x(other) whenever a link on this var goes
 *   (unlinked, replaced, or the other end died). Not called on a holder being destroyed.
 * - `keyed` + `keyed_target`: auto-linked by id. When the holder or a `keyed_target` instance
 *   materializes, the view links to the targets whose key (their rel_key() var) equals the
 *   holder's var `keyed`.
 * - `watch`: list(nameof(/target/type::var), ...), the target vars the holder's reactive procs
 *   (draw, should_run, hidden_verbs, tgui_data, needs procs) read. While linked, a changed() of the
 *   target (every TRACKED setter raises one) marks the holder changed too.
 */
/proc/rel_one(var_name, type = null, kind = null, back = null, other_deleted = CLEAR, on_unlink = null, keyed = null, keyed_target = null, list/watch = null, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE, policy = OWN_DELETE, starts = null)
	return _rel_kind_decl(var_name, FALSE, type, kind, back, other_deleted, on_unlink, keyed, keyed_target, watch, keep_after_destroy, pool_reset, forward, policy, starts)

/// A list relation view: var_name lists any number of entities, each dropped when it dies. The
/// options are rel_one()'s; with `back` naming this same var the membership is symmetric (linking
/// A to B lists each in the other's var).
/proc/rel_many(var_name, type = null, kind = null, back = null, other_deleted = CLEAR, on_unlink = null, keyed = null, keyed_target = null, list/watch = null, keep_after_destroy = FALSE, pool_reset = FALSE, forward = FALSE, policy = OWN_DELETE, starts = null)
	return _rel_kind_decl(var_name, TRUE, type, kind, back, other_deleted, on_unlink, keyed, keyed_target, watch, keep_after_destroy, pool_reset, forward, policy, starts)

/**
 * rel_one() / rel_many() with the declared kind. `type` is the type of what the var holds (a path; null: untyped).
 * Every accessor write checks it (own_type_ok()): a value that is not null or an istype() of it is refused and reported. `kind`:
 *   RELK_REF     a plain reference, cleared when the other end dies (the default);
 *   RELK_PAIRED  both ends name each other: needs back =, and one rel_link() writes both sides;
 *   RELK_OWNED   the holder owns the value(s) and deletes them with itself (owns()); `policy` is owns()'s
 *                (OWN_DELETE, or OWN_SPILL for a part that drops out when the holder is destroyed, or
 *                OWN_PRIVATE_COPY for a var holding a registered prototype or a private copy of one), and
 *                `starts` its starting occupant (owns(starts =)):
 *                  rel_one(nameof(cell), /obj/item/cell, kind = RELK_OWNED, policy = OWN_SPILL, starts = nameof(cell_type))
 * Giving back = without a kind means RELK_PAIRED. Every write of a view publishes both ends.
 */
/proc/_rel_kind_decl(var_name, is_list, type, kind, back, other_deleted, on_unlink, keyed, keyed_target, list/watch, keep_after_destroy, pool_reset, forward, policy = OWN_DELETE, starts = null)
	if(isnull(kind))
		kind = back ? RELK_PAIRED : RELK_REF
	if(!isnull(starts) && kind != RELK_OWNED)
		CRASH("rel_one/rel_many([var_name]): starts = is only for RELK_OWNED (a starting occupant is owned)")
	switch(kind)
		if(RELK_OWNED)
			return owns(var_name, policy = policy, keep_after_destroy = keep_after_destroy, pool_reset = pool_reset, forward = forward, type = type, starts = starts)
		if(RELK_PAIRED)
			if(!back)
				CRASH("rel_one/rel_many([var_name]): RELK_PAIRED needs back = nameof(/other/type::var)")
		if(RELK_REF)
			if(back)
				CRASH("rel_one/rel_many([var_name]): back = is only for RELK_PAIRED")
		else
			CRASH("rel_one/rel_many([var_name]): kind [kind] is not RELK_REF, RELK_PAIRED or RELK_OWNED")
	return _rel_decl(var_name, is_list, type, back, other_deleted, on_unlink, keyed, keyed_target, watch, keep_after_destroy, pool_reset, forward)

/// A keyed target: instances of this type are found by keyed relations (rel_one/rel_many with
/// `keyed_target =` this type) through their var `key_var`.
/proc/rel_key(key_var)
	var/datum/own_entry/E = new
	E.keyed_key = key_var
	return E

/proc/_rel_decl(var_name, is_list, type, back, other_deleted, on_unlink, keyed, keyed_target, list/watch, keep_after_destroy, pool_reset, forward)
	var/shape = RELS_PLAIN
	if(back)
		shape = (is_list && back == var_name) ? RELS_SYMMETRIC : RELS_PAIR
	var/extra = null
	if(keyed_target)
		if(!keyed)
			CRASH("rel_one/rel_many([var_name]): keyed_target needs keyed = nameof(our key var)")
		extra = list(keyed_target, keyed)
	var/list/entry = list(OWNK_REL, shape, back, extra, !!is_list, length(watch) ? watch.Copy() : null, other_deleted || CLEAR, on_unlink, type)
	return _own_entry(var_name, entry, keep_after_destroy, pool_reset, forward)

/// The declarations collected from one type's ownership() and relations() lists.
/datum/own_decls
	/// var name -> entry list(kind, arg, partner, extra, is_list, watch, other_deleted, on_unlink)
	var/list/entries = list() // ALLOW(instance_list): one per declaring type, always filled by the collector and handed to the table
	/// "var: ..." lines for a var declared with two kinds across the hierarchy.
	var/list/conflicts
	/// Annotations: keep_after_destroy / pool_reset / forward var names.
	var/list/keep
	var/list/pool_reset
	var/list/forward
	/// rel_key(): instances are keyed targets found through `key`.
	var/keyed_key
	/// var name -> starting occupant spec (owns(starts =)); a later declaration (a subtype's) replaces an earlier one.
	var/list/starts

/// Records one declaration. One kind per var across the hierarchy: a subtype may change an own
/// policy or a relation's options, never the kind. A conflict is reported when the table is built.
/datum/own_decls/proc/add(datum/own_entry/E)
	if(!istype(E))
		LAZYADD(conflicts, "[E]: not an owns()/shares()/proto()/rel_one()/rel_many()/rel_key() entry")
		return
	if(E.keyed_key)
		keyed_key = E.keyed_key
		return
	var/var_name = E.var_name
	if(E.keep_after_destroy)
		LAZYOR(keep, var_name)
	if(E.pool_reset)
		LAZYOR(pool_reset, var_name)
	if(E.forward)
		LAZYOR(forward, var_name)
	if(!isnull(E.starts))
		LAZYSET(starts, var_name, E.starts)
	var/list/entry = E.entry
	if(!entry)
		return
	var/list/old = entries[var_name]
	if(old && old[OWNE_KIND] != entry[OWNE_KIND])
		LAZYADD(conflicts, "[var_name]: declared [own_kind_name(old[OWNE_KIND])] by an ancestor and [own_kind_name(entry[OWNE_KIND])] here")
	entries[var_name] = entry

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
	/// TRUE when the type declares nothing to tear down (the fast path).
	var/empty = TRUE
	/// TRUE when materialize/dematerialize has keyed-link work (keyed views, or a keyed target).
	var/materialize_work = FALSE
	/// forward-annotated var names (om_forward_state()), or null.
	var/list/forward_vars
	/// The key var when instances are keyed targets (rel_key()), or null.
	var/keyed_key
	/// REL vars declared with watch =, or null.
	var/list/watch_vars
	/// var name -> starting occupant spec (owns(starts =)), made by own_init_starts() at init, or null.
	var/list/start_vars
	/// ENGINE_HOOK_*: the engine work the type's compiled declarations (code/engine/declare) ask for at init, or 0.
	var/engine_hooks = 0

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
	// Capabilities contribute first (a slot owns its var); the type's own lists come after.
	if(isatom(D))
		for(var/datum/capability/C as anything in caps_of(D))
			for(var/datum/own_entry/E as anything in C.owned())
				decl.add(E)
	for(var/datum/own_entry/E as anything in type_list(D, TYPE_PROC_REF(/datum, ownership)))
		decl.add(E)
	for(var/datum/own_entry/E as anything in type_list(D, TYPE_PROC_REF(/datum, relations)))
		decl.add(E)
	// The engine's declarations: the relation entries of the type's CAPABILITIES lists (code/engine/declare/relations.dm).
	for(var/datum/own_entry/E as anything in table_own_entries(table_of(D)))
		decl.add(E)
	for(var/line in decl.conflicts)
		OWN_REPORT("[D.type]: one kind per var: [line]")
	T.entries = decl.entries
	for(var/var_name in T.entries)
		var/list/entry = T.entries[var_name]
		if(!(var_name in D.vars))
			OWN_REPORT("[D.type] declares [own_kind_name(entry[OWNE_KIND])] var '[var_name]', which it doesn't have")
			continue
		// rel_*() dispatches OWN, then LIST_STATE, then the relation view: a var declared in two of those tables has an undefined winner. Logged, never fatal.
		if(list_state_of(D, var_name))
			log_world("REL OVERLAP: [D.type].[var_name] is declared [own_kind_name(entry[OWNE_KIND])] and LIST_STATE; rel_*() will use the ownership declaration and ignore the LIST_STATE one")
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
	link_entries_for(decl, D, T)
	T.engine_hooks = table_hook_flags(table_of(D))
	T.keep_vars = decl.keep
	T.pool_reset_vars = decl.pool_reset
	T.forward_vars = decl.forward
	T.keyed_key = decl.keyed_key
	for(var/var_name in decl.starts)
		if(!(var_name in D.vars))
			OWN_REPORT("[D.type] declares a starting occupant for var '[var_name]', which it doesn't have")
			continue
		var/list/start_entry = T.entries[var_name]
		if(start_entry && start_entry[OWNE_KIND] != OWNK_OWN)
			OWN_REPORT("[D.type].[var_name]: a starting occupant is owned, but the var is declared [own_kind_name(start_entry[OWNE_KIND])]")
			continue
		if(decl.starts[var_name] == STARTS_NONE)
			continue // a subtype cancelled the occupant an ancestor declared
		LAZYSET(T.start_vars, var_name, decl.starts[var_name])
	if(T.keyed_key && !(T.keyed_key in D.vars))
		OWN_REPORT("[D.type] is a keyed target through var '[T.keyed_key]', which it doesn't have")
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
				if(!by_proc && !(policy in list(OWN_DELETE, OWN_SPILL, OWN_CONTAINED, OWN_KEEP, OWN_HAND_OVER)))
					OWN_REPORT("[D.type].[var_name]: unknown teardown policy [policy]")
				var/list/hand_to = own_entry_successor(entry)
				if(hand_to && !(hand_to[1] in D.vars))
					OWN_REPORT("[D.type].[var_name]: owns() to [hand_to[1]] is not a var")
				if(!hand_to && (policy == OWN_HAND_OVER || entry[OWNE_EXTRA] == OWN_HAND_OVER))
					OWN_REPORT("[D.type].[var_name]: OWN_HAND_OVER needs successor = and successor_var =")
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
	// A type that declares reading this var (or hopping over it) re-derives what reads it (derived.dm).
	if(GLOB?.derived_read_vars?[var_name])
		derived_var_touched(holder, var_name)
	// A relation var some stat reads through, or contributes to a stat across: the stat layer follows it.
	if(holder && GLOB?.stat_input_keys?[var_name])
		stat_relation_changed(holder, var_name)
		stat_inputs_changed(holder, var_name)
	// A relation write publishes each end it touches (both ends of a paired view call this).
	if(holder && READERS(holder, var_name))
		publish_change(holder, var_name)
	var/datum/om/registry/R = GLOB?.om_reg
	if(!R || !holder)
		return
	var/list/fields = R.fields_by_type[holder.type] || R.fields_of(holder.type)
	var/channel = fields[var_name]
	if(channel)
		changed(holder, channel)

/// The bare name of a proc path (/obj/foo/proc/bar -> "bar").
/proc/own_proc_name(proc_path)
	var/text = "[proc_path]"
	var/slash = findlasttext(text, "/")
	return slash ? copytext(text, slash + 1) : text

/// The declaration entry for `var_name` on `holder`, or null.
/proc/own_entry(datum/holder, var_name)
	return own_table_of(holder).entries[var_name]

/// The entry for holder.var_name, which must be of `kind`. An undeclared owned var is reported and null returned: an owned var is
/// declared (owns_one / owns_many, with `starts =` for a starting occupant). An undeclared relation is learned: the first
/// rel_set()/rel_add() records an implicit rel() in the type's table (ownership.md §7: declarations are only for exceptions).
/// A var of another kind is reported and null is returned.
/proc/own_entry_of_kind(datum/holder, var_name, kind, is_list = FALSE)
	var/datum/own_table/T = own_table_of(holder)
	var/list/entry = T.entries[var_name]
	if(!entry)
		if(!(var_name in holder.vars))
			OWN_REPORT("[holder.type] has no var '[var_name]'")
			return null
		switch(kind)
			if(OWNK_REL)
				entry = list(OWNK_REL, RELS_PLAIN, null, null, is_list, null, CLEAR, null, null)
				LAZYADD(T.ref_vars, var_name)
			if(OWNK_OWN)
				OWN_REPORT("[holder.type].[var_name] is written as an owned var but not declared: add owns_one / owns_many to the type's CAPABILITIES list")
				return null
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


/// Review 2 M8: an accessor write marks the holder changed (refresh.dm). Writes made while the
/// globals are still being built (a global datum's New()) come before the refresh queue exists and
/// before anything is drawn, so they mark nothing.
/proc/own_mark_changed(datum/holder, var_name)
	if(!islist(GLOB?.refresh_queue))
		return
	changed(holder, CHANGE_EXPLICIT, var_name)

/// TRUE when `value` may be written to holder.var_name under `entry`: null, an untyped declaration, or an istype() of
/// the declared `type` (rel_one/rel_many(type =)). A mismatch is reported (a stack_trace, which fails a test run)
/// and the caller refuses the write. `entry` may be null (an undeclared view is untyped).
/proc/own_type_ok(datum/holder, var_name, list/entry, value)
	if(isnull(value) || !entry)
		return TRUE
	var/type = entry[OWNE_TYPE]
	if(!type || istype(value, type))
		return TRUE
	var/datum/D = value
	OWN_REPORT("[holder.type].[var_name] is declared [type], refused [isdatum(value) ? "a [D.type]" : "[value]"]")
	return FALSE
