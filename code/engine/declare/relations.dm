// Declared relations and their write verbs (doc/rewrite/final_api.html, section 6 "References and lifecycle", section 4 "Per-instance
// lists"; section 19 "E1, declarations": "relation entries (ref_*, owns_*, link, slot) and the rel_* writers over today's ownership
// store, with teardown's destroy transaction; LIST_STATE with its four dimensions; init forms").
//
// The relation entries of a CAPABILITIES list (ref_one, ref_many, owns_one, owns_many, link) are turned into the entries of today's
// ownership table (code/datums/ownership/table.dm), so the destroy transaction, the reverse indexes and the teardown guard keep working
// unchanged: a declared owned var is torn down by its on_destroy, a reference is cleared when the other end dies. The write verbs
// below are the design's one set: each dispatches on the declared kind, so the caller never remembers how a var was declared.

/// Applies a declared on_destroy to the legacy policy ids.
/proc/relation_policy(on_destroy)
	switch(on_destroy)
		if(ON_DESTROY_SPILL)
			return OWN_SPILL
		if(ON_DESTROY_PRIVATE_COPY)
			return OWN_PRIVATE_COPY
		if(ON_DESTROY_HAND_OVER)
			return OWN_HAND_OVER
	return OWN_DELETE

/// The legacy own entries one type's compiled table declares, in declaration order: what build_own_table() adds beside the type's
/// ownership() and relations() lists.
/proc/table_own_entries(datum/type_table/T)
	. = list()
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(!istype(E))
			continue
		switch(E.kind)
			if(ENTRY_REF_ONE, ENTRY_REF_MANY)
				var/by = E.args["by"]
				var/on_deleted = E.args["on_other_deleted"] == OTHER_DELETE_ME ? DELETE_ME : CLEAR
				. += _rel_decl(E.args["var"], E.kind == ENTRY_REF_MANY, E.args["type"], null, on_deleted, E.args["on_unlink"], by, by ? E.args["type"] : null, null, FALSE, FALSE, FALSE)
				if(by)
					keyed_target_register(E.args["type"], E.args["target_key"] || by)
			if(ENTRY_OWNS_ONE, ENTRY_OWNS_MANY)
				var/policy = relation_policy(E.args["on_destroy"])
				var/starts = relation_starts(E)
				if(policy == OWN_PRIVATE_COPY)
					. += proto(E.args["var"])
				else
					. += owns(E.args["var"], policy = policy, type = E.args["type"], starts = starts, is_list = (E.kind == ENTRY_OWNS_MANY), if_var = E.args["only_if"], else_policy = relation_policy(E.args["otherwise"]), successor = E.args["successor"], successor_var = E.args["successor_var"])

/// The starts = of an owns_* entry as the legacy table keeps it: a type, a list, a var name, or a starts spec entry (pick_one, a proc,
/// when(), with starts_args) that own_init_starts() resolves at init.
/proc/relation_starts(datum/entry/E)
	var/starts = E.args["starts"]
	var/starts_args = E.args["starts_args"]
	if(isnull(starts))
		return null
	if(starts_args || istype(starts, /datum/entry))
		return entry_make("starts", null, list("value" = starts, "args" = starts_args))
	return starts

/// The text a starting-occupant spec adds to an own entry's interning signature: an entry spec by its own signature.
/proc/starts_signature(starts)
	if(istype(starts, /datum/entry))
		var/datum/entry/E = starts
		return "entry:[E.sig]"
	return "[starts]"

/// starts = pick_one(list(/obj/item/a = 3, /obj/item/b = 1)): a random pick weighted by the values, made when the holder initializes.
/proc/pick_one(list/weighted)
	return entry_make("pick_one", null, list("weights" = weighted))

/// Resolves a starts spec entry for holder D into a type path (or a list of paths) and the constructor arguments.
/proc/starts_resolve(datum/D, datum/entry/spec)
	var/value = spec
	var/list/ctor_args = null
	if(spec.kind == "starts") // owns_one()/owns_many() wrap the spec with its starts_args; a legacy owns(starts = when()/pick_one()) passes it bare
		value = spec.args["value"]
		ctor_args = spec.args["args"]
	if(istype(value, /datum/entry))
		var/datum/entry/inner = value
		switch(inner.kind)
			if("pick_one")
				value = pickweight(inner.args["weights"])
			if(ENTRY_WHEN)
				value = starts_when(D, inner)
	if(istext(value))
		value = (value in D.vars) ? D.vars[value] : call(D, value)(null)
	return list(value, ctor_args)

/**
 * What a starts = spec makes for `holder` when it initializes: a list of new instances, empty when it makes nothing. Every form of section 6
 * "Starting contents": a type; nameof(var) of a holder var holding one (a mapper's edit wins); list(T...) or list(T = n); pick_one(list);
 * when(cond, T); PROC_REF(x), where x(datum/act/A) answers a type, an instance or a list of them. The instances are made at `loc` (null:
 * nullspace, for contents moved in through the relation write) with `starts_args` after it as the constructor's arguments. Used by slot()
 * and the capabilities built on a slot (cell_bay()); owns_one/owns_many keep own_init_starts(), which reads the same specs.
 */
/proc/starts_make(datum/holder, starts, list/starts_args, loc)
	. = list()
	starts_args = starts_args_resolve(holder, starts_args) // OWNER is the holder (code/engine/lifeforms/contents.dm)
	if(istype(starts, /datum/entry))
		var/datum/entry/inner = starts
		switch(inner.kind)
			if("pick_one")
				var/list/weights = inner.args["weights"]
				starts = pickweight(weights.Copy())
			if(ENTRY_WHEN)
				starts = starts_when(holder, inner)
			if("starts")
				return starts_make(holder, inner.args["value"], inner.args["args"] || starts_args, loc)
			else
				declare_report("starts = [inner.kind](): not a starting-contents form on [holder.type]")
				return
	if(istext(starts))
		if(starts in holder.vars)
			starts = holder.vars[starts]
		else if(hascall(holder, starts))
			starts = call(holder, starts)(null)
		else
			declare_report("starts = \"[starts]\": [holder.type] has no such var or proc")
			return
	if(isnull(starts))
		return
	if(isdatum(starts))
		. += starts
		return
	if(islist(starts))
		var/list/many = starts
		for(var/item in many)
			var/count = (!isnum(item) && isnum(many[item])) ? many[item] : 1
			for(var/i in 1 to count)
				. += starts_make(holder, item, starts_args, loc)
		return
	if(ispath(starts))
		. += length(starts_args) ? new starts(arglist(list(loc) + starts_args)) : new starts(loc)

/// slot(id, starts =, starts_args =) entries: what each starts with is made in nullspace and moved into the slot through the one transfer
/// (forced: nothing a player does is being checked). A holder whose type has no ledger slot of that id keeps the thing as plain contents. Runs
/// in the engine init (step 4 of section 6's order: after on_holder_preinit, before on_holder_init).
/proc/slot_starts_init(datum/holder, datum/type_table/T)
	if(!isatom(holder))
		return
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_SLOT))
		var/datum/entry/E = C.item
		if(isnull(E.args["starts"]) || !op_whens_hold(holder, C.whens))
			continue
		var/slot_id = E.args["id"]
		for(var/atom/movable/thing in starts_make(holder, E.args["starts"], E.args["starts_args"], null))
			if(!move_into(holder, slot_id, thing, force = TRUE))
				thing.place_starting_occupant(holder)

/// when(cond, T) as a starts value: the type if the condition holds at init, else nothing.
/proc/starts_when(datum/D, datum/entry/when_entry)
	var/cond = when_entry.args["cond"]
	if(!condition_holds(D, cond))
		return null
	return length(when_entry.children) ? when_entry.children[1] : null

/// A condition of section 5 evaluated now on `holder`: nameof(v) (a truthy var), a stat or key id, not()/all_of()/any_of(), PROC_REF.
/proc/condition_holds(datum/holder, cond)
	if(islist(cond))
		var/list/L = cond
		switch(L[1])
			if("not")
				return !condition_holds(holder, L[2])
			if("all")
				for(var/i in 2 to length(L))
					if(!condition_holds(holder, L[i]))
						return FALSE
				return TRUE
			if("any")
				for(var/i in 2 to length(L))
					if(condition_holds(holder, L[i]))
						return TRUE
				return FALSE
		return FALSE
	if(isnum(cond))
		return condition_id_holds(holder, cond)
	if(istext(cond))
		if(cond in holder.vars)
			return !!holder.vars[cond]
		return !!op_pure_call(holder, cond)
	return !!cond

/// A numeric condition id: a capability state key (CAPKEY_ID) or, once E3 lands, a stat id. The default reads the key on the holder.
/proc/condition_id_holds(datum/holder, id)
	if(id >= STAT_ID_BASE && id < CAPKEY_ID_BASE)
		return !!stat_value(holder, id)
	if(id > 255)
		return cap_key_get(holder, id)
	return FALSE

/// not(), all_of() and any_of() are the requirement language's names (E2 owns them); a condition tree of the stat and activation layers is
/// written with these until the two meet.
/proc/cond_not(cond)
	return list("not", cond)

/proc/cond_all(...)
	return list("all") + args

/proc/cond_any(...)
	return list("any") + args

// ---- link: a pair declared once for both types ----

/// Statics, not GLOB lists: tables are built while the globals are still being made (a global datum's New()), so what a build reads
/// must not depend on the global init order.
/// signature -> the link entry
/proc/link_decls_cache()
	RETURN_TYPE(/list)
	var/static/list/cache = list() // ALLOW(cache,sys_static_getter): a mutable static, not a GLOB list, because the declaration tables are built while the globals are still being made
	return cache

/// target type -> the id var holders key on
/proc/keyed_targets_cache()
	RETURN_TYPE(/list)
	var/static/list/cache = list() // ALLOW(cache,sys_static_getter): a mutable static, not a GLOB list, because the declaration tables are built while the globals are still being made
	return cache

/// Registers a paired relation. Both ends become declarations of their types' ownership tables: tables already built are patched,
/// tables built later read link_decls_cache().
/proc/link_register(datum/entry/E)
	if(link_decls_cache()[E.sig])
		return
	link_decls_cache()[E.sig] = E
	if(E.args["hot"] || E.args["sparse"])
		return // an engine hot-path pair (direct lists, no index, nothing published; the engine owns both sides), or a sparse one (link_state.dm): no vars to patch in
	var/list/cache = _scs_own_table
	for(var/type_key in cache)
		var/datum/own_table/T = cache[type_key]
		if(istype(T))
			link_patch_table(T, E)

/// Adds `E`'s ends to an ownership table when its owner type is (a subtype of) an end's type.
/proc/link_patch_table(datum/own_table/T, datum/entry/E)
	if(E.args["sparse"])
		return // its ends are keys in the holders' engine records (link_state.dm), not vars of a table
	for(var/end in list("a", "b"))
		var/end_type = E.args["[end]_type"]
		if(!ispath(T.owner_type, end_type))
			continue
		var/other = end == "a" ? "b" : "a"
		var/var_name = E.args["[end]_var"]
		var/back = E.args["[other]_var"]
		if(T.entries[var_name])
			continue
		var/is_list = !!E.args["[end]_many"]
		var/shape = RELS_PAIR
		if(is_list && E.args["a_type"] == E.args["b_type"] && E.args["a_var"] == E.args["b_var"])
			shape = RELS_SYMMETRIC
		var/on_deleted = E.args["[end]_on_other_deleted"] == OTHER_DELETE_ME ? DELETE_ME : CLEAR
		var/list/entry = list(OWNK_REL, shape, back, null, is_list, null, on_deleted, E.args["[end]_on_unlink"], E.args["[other]_type"])
		T.entries[var_name] = entry
		LAZYADD(T.ref_vars, var_name)
		T.empty = FALSE

/// Remembers that instances of `type` are found by keyed relations through var `id_var` (ref_one(by =)).
/proc/keyed_target_register(type, id_var)
	keyed_targets_cache()[type] = id_var

/// The keyed targets every CAPABILITIES list declares (generated: declared_keyed_targets()), read once. A target type is keyed whichever side builds its
/// table first (a door placed on the map before its button), so a table asks this list, not only the holders' tables built so far. A static, not a
/// global: tables are built while the globals are still being made.
/proc/keyed_targets_declared()
	var/static/list/declared // ALLOW(sys_static_getter): the generated keyed-target table, read once on the first table build, which can come during global init
	if(isnull(declared))
		declared = declared_keyed_targets()
	return declared

/// The link ends and keyed-target declaration that apply to D's type: what build_own_table() adds after the type's own entries.
/proc/link_entries_for(datum/own_decls/decl, datum/D, datum/own_table/T)
	var/list/declared = keyed_targets_declared()
	for(var/target_type in declared)
		if(istype(D, target_type) && !decl.keyed_key)
			decl.keyed_key = declared[target_type]
	for(var/sig in link_decls_cache())
		link_patch_table(T, link_decls_cache()[sig])
	for(var/target_type in keyed_targets_cache())
		if(istype(D, target_type) && !decl.keyed_key)
			decl.keyed_key = keyed_targets_cache()[target_type]

// ---- the write verbs: one set, dispatching on the declared kind ----

/// The declared kind of holder.var_name (OWNK_*), or 0 when undeclared.
/proc/rel_kind(datum/E, var_name)
	var/list/entry = own_table_of(E).entries[var_name]
	return entry ? entry[OWNE_KIND] : 0

/// Stores `value` (or null). Accepts ref_one, owns_one, a single link end and a registry-typed var.
/proc/rel_set(datum/E, var_name, datum/value)
	// Nothing changes (a New() linking null into an empty view): no table needed, which also keeps datums made during global init off it.
	if(E.vars[var_name] == value)
		return value
	switch(rel_kind(E, var_name))
		if(OWNK_OWN)
			return _own_set(E, var_name, value)
		if(OWNK_PROTO)
			return proto_set(E, var_name, value)
	var/list_state = list_state_of(E, var_name)
	if(list_state)
		return list_state_set(E, var_name, value, list_state)
	. = rel_view_set(E, var_name, value)
	activations_relation_changed(E, var_name)

/// Adds one member. `key` puts it under a key in an associative owns_many.
/proc/rel_add(datum/E, var_name, datum/value, key = null)
	switch(rel_kind(E, var_name))
		if(OWNK_OWN)
			return isnull(key) ? _own_add(E, var_name, value) : _own_put(E, var_name, key, value)
	var/list_state = list_state_of(E, var_name)
	if(list_state)
		return list_state_add(E, var_name, value, key, list_state)
	return rel_view_add(E, var_name, value)

/// Drops one member; an owned member is disposed of by on_destroy (rel_take keeps it).
/proc/rel_remove(datum/E, var_name, datum/value)
	switch(rel_kind(E, var_name))
		if(OWNK_OWN)
			return own_remove(E, var_name, value)
	var/list_state = list_state_of(E, var_name)
	if(list_state)
		return list_state_remove(E, var_name, value, list_state)
	return rel_view_remove(E, var_name, value)

/// Empties the var: owned values are disposed of by on_destroy, links are unlinked on both sides. `policy` (an OWN_* constant) overrides what the
/// declaration says for this one call, on an owned var (an explicit delete over a CONTAINED / SPILL / KEEP declaration).
/proc/rel_clear(datum/E, var_name, policy = null)
	switch(rel_kind(E, var_name))
		if(OWNK_OWN)
			return own_clear(E, var_name, policy)
	var/list_state = list_state_of(E, var_name)
	if(list_state)
		return list_state_clear(E, var_name, list_state)
	. = rel_view_clear(E, var_name)
	activations_relation_changed(E, var_name)

/// Is the var a list by declaration (an owns_many / list-typed var) or by what it holds now?
/proc/rel_is_list_shaped(datum/E, var_name)
	var/list/entry = own_table_of(E).entries[var_name]
	if(entry && entry[OWNE_LIST])
		return TRUE
	return islist(E.vars[var_name]) || !isnull(list_state_of(E, var_name))

/// Detaches one value without disposing of it and returns it unowned. On a many, `member` picks one and `key` one keyed member. A many with neither
/// (a null member or key included: DM cannot tell "omitted" from "passed null") detaches NOTHING and returns null: taking everything is
/// rel_take_all(), never an accident of a null argument. A one-shape var is taken whole.
/proc/rel_take(datum/E, var_name, member = null, key = null)
	if(!isnull(member))
		return own_take_member(E, var_name, member)
	if(!isnull(key))
		return own_take_member(E, var_name, key)
	if(rel_is_list_shaped(E, var_name))
		log_world("REL: rel_take([E.type], [var_name]) with no member or key on a list var took nothing (use rel_take_all() to take every member)")
		return null
	return own_take(E, var_name)

/// Detaches every member of a many (or the one value of a one-shape var) without disposing of them and returns them as a fresh list, always: empty when
/// the var holds nothing, whether it is declared eager or lazy.
/proc/rel_take_all(datum/E, var_name)
	if(!rel_is_list_shaped(E, var_name))
		var/taken = own_take(E, var_name)
		return isnull(taken) ? list() : list(taken)
	var/list/taken_all = own_take_all(E, var_name)
	return islist(taken_all) ? taken_all : list()

/// Re-owns a value in one write, so it is never destroyed or orphaned on the way.
/proc/rel_move(datum/old_holder, var_a, datum/new_holder, var_b, member = null, key = null)
	return own_transfer(old_holder, var_a, new_holder, var_b, member, key)

/// The holder's private copy of an owns_one(copy_on_write = TRUE) var, made on the first call.
/proc/rel_private(datum/E, var_name)
	return proto_private(E, var_name)

/// Whether the holder has a private copy of a copy-on-write var.
/proc/rel_is_private(datum/E, var_name)
	return proto_is_private(E, var_name)

// ---- LIST_STATE: a per-instance list declared with four independent policies ----
// LIST_STATE(T, var, alloc = ALLOC_LAZY | ALLOC_EAGER, kind = KIND_LIST | KIND_SET | KIND_MAP, owns = OWNS_NONE | OWNS_ROWS,
//            share = SHARE_NONE | SHARE_COW_TABLE, row = /datum/record/x, empty_differs = TRUE)



/datum/list_state_decl/proc/spec()
	return null

/// One declared list's policies.
/datum/list_state
	var/owner_type
	var/var_name
	var/alloc = ALLOC_LAZY
	var/kind = KIND_LIST
	var/owns = OWNS_NONE
	var/share = SHARE_NONE
	var/row
	var/empty_differs = FALSE

GLOBAL_LIST_EMPTY(list_states) // "[type]|[var]" -> /datum/list_state; built on first use
GLOBAL_VAR_INIT(list_states_built, FALSE)

/proc/list_states_build()
	GLOB.list_states_built = TRUE
	for(var/decl_type in subtypesof(/datum/list_state_decl))
		var/datum/list_state_decl/D = new decl_type
		var/list/row = D.spec()
		if(!length(row))
			continue
		var/list/opts = row[3]
		var/datum/list_state/S = new
		S.owner_type = row[1]
		S.var_name = row[2]
		S.alloc = opts["alloc"] || ALLOC_LAZY
		S.kind = opts["kind"] || KIND_LIST
		S.owns = opts["owns"] || OWNS_NONE
		S.share = opts["share"] || SHARE_NONE
		S.row = opts["row"]
		S.empty_differs = !!opts["empty_differs"]
		if(S.owns == OWNS_ROWS && !S.row)
			declare_report("LIST_STATE([S.owner_type], [S.var_name]): owns = OWNS_ROWS needs row = /datum/record/x")
		if(S.empty_differs && S.alloc != ALLOC_LAZY)
			declare_report("LIST_STATE([S.owner_type], [S.var_name]): empty_differs applies to alloc = ALLOC_LAZY only")
		GLOB.list_states["[S.owner_type]|[S.var_name]"] = S

/// The LIST_STATE declaration of E's var (the nearest ancestor type that declares it), or null. Cached per (type, var).
/proc/list_state_of(datum/E, var_name)
	if(!islist(GLOB?.list_states) || !islist(GLOB.list_state_cache))
		return null
	if(!GLOB.list_states_built)
		list_states_build()
	if(!length(GLOB.list_states))
		return null
	var/list/by_var = GLOB.list_state_cache[E.type]
	if(isnull(by_var))
		by_var = list()
		GLOB.list_state_cache[E.type] = by_var
	if(var_name in by_var)
		return by_var[var_name]
	var/datum/list_state/found = null
	var/best = 0
	for(var/key in GLOB.list_states)
		var/datum/list_state/S = GLOB.list_states[key]
		if(S.var_name == var_name && istype(E, S.owner_type))
			var/depth = length(splittext("[S.owner_type]", "/"))
			if(depth > best)
				best = depth
				found = S
	by_var[var_name] = found
	return found

GLOBAL_LIST_EMPTY(list_state_cache) // type -> list(var -> /datum/list_state or null) // ALLOW(cache): the declaration engine's per-type lookup memo, not a shared cache of values

/// The list to write into: allocated on first use, or copied from a shared table (share = SHARE_COW_TABLE) on the first write.
/proc/list_state_writable(datum/E, var_name, datum/list_state/S)
	var/list/L = E.vars[var_name]
	if(isnull(L))
		L = list()
		E.vars[var_name] = L // ALLOW(api): this proc is the accessor for a LIST_STATE var: the one place allowed to write this var by name
	else if(S.share == SHARE_COW_TABLE && !E.rx?.cow_private?[var_name])
		L = L.Copy()
		E.vars[var_name] = L // ALLOW(api): copy on first write of a shared per-type table
		LAZYSET(rx_of(E).cow_private, var_name, TRUE)
	return L

/datum/rx_state
	/// Which SHARE_COW_TABLE lists this instance has copied already.
	var/list/cow_private

/// A write finished on a LIST_STATE var: a lazy list that emptied goes back to null (unless empty_differs), and the change publishes.
/proc/list_state_written(datum/E, var_name, datum/list_state/S)
	var/list/L = E.vars[var_name]
	if(S.alloc == ALLOC_LAZY && !S.empty_differs && islist(L) && !length(L))
		E.vars[var_name] = null // ALLOW(api): a lazy list that emptied is null again
	own_field_changed(E, var_name)
	engine_key_changed(E, var_name)

/proc/list_state_add(datum/E, var_name, value, key, datum/list_state/S)
	var/list/L = list_state_writable(E, var_name, S)
	if(S.owns == OWNS_ROWS && isdatum(value))
		own_stamp(value, E, var_name)
	switch(S.kind)
		if(KIND_SET)
			if(value in L)
				return value
			L += list(value)
		if(KIND_MAP)
			if(isnull(key))
				declare_report("rel_add([E.type].[var_name]): a map needs key =")
				return null
			L[key] = value
		else
			L += list(value)
	list_state_written(E, var_name, S)
	return value

/proc/list_state_remove(datum/E, var_name, value, datum/list_state/S)
	var/list/L = E.vars[var_name]
	if(!islist(L))
		return FALSE
	if(!(value in L))
		return FALSE
	L = list_state_writable(E, var_name, S)
	L -= value
	if(S.owns == OWNS_ROWS && isdatum(value))
		own_unstamp(value)
		qdel(value) // ALLOW(lifecycle): an owned row is disposed of by the list that owned it
	list_state_written(E, var_name, S)
	return TRUE

/proc/list_state_clear(datum/E, var_name, datum/list_state/S)
	var/list/L = E.vars[var_name]
	if(!islist(L))
		return
	if(S.owns == OWNS_ROWS)
		for(var/key in L)
			var/datum/row = isdatum(key) ? key : L[key]
			if(isdatum(row))
				own_unstamp(row)
				qdel(row) // ALLOW(lifecycle): an owned row is disposed of by the list that owned it
	if(S.share == SHARE_COW_TABLE && !E.rx?.cow_private?[var_name])
		E.vars[var_name] = null // ALLOW(api): clearing a shared table drops the reference, never edits the table
	else
		L.Cut()
	list_state_written(E, var_name, S)

/proc/list_state_set(datum/E, var_name, value, datum/list_state/S)
	if(!islist(value) && !isnull(value))
		declare_report("rel_set([E.type].[var_name]): a LIST_STATE var takes a list or null")
		return null
	E.vars[var_name] = value // ALLOW(api): replacing a shared table is rel_set on the declared list var
	if(S.share == SHARE_COW_TABLE && E.rx)
		LAZYREMOVE(E.rx.cow_private, var_name)
	list_state_written(E, var_name, S)
	return value
