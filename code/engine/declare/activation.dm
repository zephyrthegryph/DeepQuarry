// Scoped activation (doc/rewrite/final_api.html, section 5 "Scoped activation (X1)", section 11 "Definition, activation, contributions";
// section 19 "E1, declarations").
//
// Everything applied to a holder for a while is an activation: one record with a definition, a source, a holder and a scope. A
// grant, a conditional entry, a slot effect, a species' capabilities and a timed grant are not separate mechanisms with their own
// lifetime rules. There is ONE attach path (build and validate the contributions, then apply them) and ONE teardown path (end what
// it owns, remove its contributions, run on_deactivate, drop the record). A revoked activation is dead at once: dispatch skips it
// the moment revoke() returns.
//
// An activation applies the entries its definition brings by asking the /datum/entry_engine registered for each entry's kind:
// E3's contributes() applies a stat contribution, E4's on_notice() a hook, E2's op() an op. The engine for a kind that has none yet
// is skipped. `explain_activations(E)` lists what a holder carries.

/// Applies and removes one kind of entry for an activation. The engine that owns the kind subclasses this and sets `kind`.
/datum/entry_engine
	/// The entry kind this engine applies (ENTRY_* or another engine's kind).
	var/kind
	/// TRUE: a type-level entry of this kind is applied as an activation of the holder that lives while its enclosing when() conditions hold
	/// (cond_scope.dm), so the engine sees a type-level entry the way it sees a granted or slotted one, and its remove() runs when the scope ends.
	var/cond_scoped = FALSE

/// Checks an entry before anything is applied: null when it can apply, else the reason it cannot. Pure.
/datum/entry_engine/proc/validate(datum/activation/A, datum/entry/E)
	return null

/// Applies `E` for activation A (stat contributions apply at once, hooks and ops register to go live at the drain). Returns TRUE when it
/// applied something A must later remove.
/datum/entry_engine/proc/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	return FALSE

/// Removes what apply() made. A is already dead.
/datum/entry_engine/proc/remove(datum/activation/A, datum/entry/E)
	return

/// The entry engine of a declaration kind (owns_one, ref_many, ...), or null. A static, not a GLOB list: a global datum made while the
/// globals are still being built (the underwear catalog's rel_add()) compiles its table through here, before a GLOB list is made.
/proc/entry_engine_for(kind)
	RETURN_TYPE(/datum/entry_engine)
	var/static/list/engines
	if(!engines)
		engines = list()
		for(var/engine_type in subtypesof(/datum/entry_engine))
			var/datum/entry_engine/engine = new engine_type
			if(engine.kind)
				engines[engine.kind] = engine
	return engines[kind]

/// Typed per-activation capability data. A capability declares /datum/cap_data/<cap> next to itself; cap_data(A) makes it on first use.
/datum/cap_data
	/// The capability definition's data type hook: set by the capability's own subtype of this.

/// One activation: the definition applied to a holder by a source, for a scope.
/datum/activation
	/// The interned definition (a /datum/capability).
	var/datum/capability/def
	/// A datum or a SRC_* flyweight id.
	var/source
	var/datum/holder
	var/scope = SCOPE_SOURCE
	/// Attach order across the round (stacking ties go to the first attached).
	var/serial = 0
	var/dead = FALSE
	/// Whether stacking lets this activation's behaviour run (STACK all, UNIQUE the first, BEST the strongest).
	var/runs = TRUE
	/// The capability's boolean state keys, one bit per key (cap_keys).
	var/state = 0
	/// The typed per-activation data, made on first use.
	var/datum/cap_data/data
	/// Entries this activation applied through an engine: list(entry, engine) pairs, in apply order.
	var/list/applied
	/// Child activations this one owns: they end with it.
	var/list/owned
	var/datum/activation/parent
	/// A bound grant dies with its source even when timed.
	var/bound = FALSE
	var/lasts = 0
	/// Scope data: the slot id (SCOPE_SLOT), the condition entry (SCOPE_COND), the relation var (SCOPE_RELATION).
	var/scope_data

/// Counts attach order.
GLOBAL_VAR_INIT(activation_serial, 0)

/datum/rx_state
	/// The activations this datum carries as a holder (type-level ones are made lazily).
	var/list/activations
	/// The activations this datum is the source of.
	var/list/sourced
	/// var name -> the relation-scoped grants it drives (rel_grants entries applied, with the source value they came from).
	var/list/rel_scopes

/datum/source_def
	var/list/row

/datum/source_def/proc/spec()
	return null

GLOBAL_LIST_EMPTY(source_ids) // id -> name, built on first use

/// TRUE when `source` may be the source of a hold or an activation: a live datum, or a SOURCE_DEF flyweight id.
/proc/source_is_valid(source)
	if(isdatum(source))
		var/datum/D = source
		return !QDELETED(D)
	if(isnum(source))
		if(!length(GLOB.source_ids))
			for(var/def_type in subtypesof(/datum/source_def))
				var/datum/source_def/S = new def_type
				var/list/row = S.spec()
				if(length(row))
					GLOB.source_ids["[row[1]]"] = row[2]
			GLOB.source_ids["built"] = TRUE
		return !isnull(GLOB.source_ids["[source]"])
	return FALSE

/// The definition `what` names: a /datum/capability (a constructor call's result), or the one a capability type path stands for.
/// null when it is not an engine capability (a legacy grant: a verb path, a bit name).
/proc/grant_definition(what)
	if(istype(what, /datum/capability))
		var/datum/capability/def = what
		return def.cap_id ? def : null
	if(ispath(what, /datum/capability))
		var/datum/capability_info/info = capability_info_of_type(what)
		if(!info)
			return null
		var/datum/capability/def = new what
		def.cap_id = info.cap_id
		return cap_build(def, info, list())
	return null

/// The capability id a granted()/revoke() argument names, or null for a legacy form. A path names every selector.
/proc/grant_cap_id(what)
	if(istype(what, /datum/capability))
		var/datum/capability/def = what
		return def.cap_id
	if(ispath(what, /datum/capability))
		var/datum/capability_info/info = capability_info_of_type(what)
		return info?.cap_id
	return null

// ---- the attach path ----

/**
 * Applies capability `what` to `holder` from `source`: returns the activation, or null with the reason logged when the attach fails.
 * `lasts` (deciseconds of the holder's clock) ends it at that time or with its source, whichever comes first. `bound` is accepted for
 * the hold forms and has no extra effect on a grant: a grant always ends with its source. `parent` is the activation that owns the new one (a
 * grants() effect running under an activation passes it): the child ends with its parent, however the parent ends.
 * A `what` that is not an engine capability (a verb path, a bit) is the legacy grant of code/datums/reactions/state.dm.
 */
/proc/grant(datum/holder, what, source, lasts, bound = FALSE, datum/activation/parent = null)
	RETURN_TYPE(/datum/activation)
	var/datum/capability/def = grant_definition(what)
	if(!def)
		return legacy_grant(holder, what, isnull(source) ? "grant" : source, lasts)
	return activation_attach(holder, def, source, lasts, SCOPE_SOURCE, null, parent)

/// The one attach path. `scope` and `scope_data` say what ends it besides revoke; `parent` is the owning activation.
/proc/activation_attach(datum/holder, datum/capability/def, source, lasts, scope, scope_data, datum/activation/parent)
	OP_PURE_GUARD("[def?.key] was granted to [holder?.type]")
	if(!isdatum(holder) || QDELETED(holder))
		declare_report("grant([def?.key]): the holder is deleted or not a datum")
		return null
	if(!source_is_valid(source))
		declare_report("grant([def.key]) on [holder.type]: the source must be a live datum or a SOURCE_DEF id, got [isnull(source) ? "null" : "[source]"]")
		return null
	if(!isnull(lasts) && (!isnum(lasts) || lasts <= 0))
		declare_report("grant([def.key]) on [holder.type]: lasts must be a positive number of deciseconds, got [lasts]")
		return null
	var/datum/rx_state/rx = rx_of(holder)
	// One source applies one definition to one holder once.
	var/datum/activation/existing = activation_find(holder, def.key, source)
	if(existing)
		if(existing.def == def && !lasts)
			return existing
		activation_end(existing)
	// Build and validate every contribution before anything is applied: a failure applies nothing.
	var/list/to_apply = activation_plan(def)
	for(var/datum/centry/C as anything in to_apply)
		var/datum/entry/E = C.item
		if(!istype(E))
			continue
		var/datum/entry_engine/engine = entry_engine_for(E.kind)
		var/reason = engine?.validate_for(null, E)
		if(reason)
			declare_report("grant([def.key]) on [holder.type]: [E.kind] entry refused: [reason]")
			return null
	var/datum/activation/A = new
	A.def = def
	A.source = source
	A.holder = holder // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	A.scope = scope
	A.scope_data = scope_data
	A.serial = ++GLOB.activation_serial
	A.parent = parent // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	A.lasts = lasts || 0
	LAZYADD(rx.activations, A) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	if(isdatum(source))
		LAZYADD(rx_of(source).sourced, A)
	if(parent)
		LAZYADD(parent.owned, A) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	TEST_REC_ACTIVATION(TEST_EVENT_ATTACH, def, source, holder)
	// Apply: contributions at once; nested capability definitions become child activations this one owns.
	for(var/datum/centry/C as anything in to_apply)
		if(istype(C.item, /datum/capability))
			activation_attach(holder, C.item, A, null, SCOPE_SOURCE, null, A)
			continue
		var/datum/entry/E = C.item
		var/datum/entry_engine/engine = entry_engine_for(E.kind)
		if(engine?.apply(A, E, C))
			LAZYADD(A.applied, list(list(E, engine)))
	def.on_activate(A)
	if(lasts)
		after(holder, lasts, GLOBAL_PROC_REF(activation_expire), key = "activation:[A.serial]", with = list(A))
	activation_restack(holder, def.key)
	return A

/// The contribution list of a definition: the entries its expansion brings (the definition itself is not in it), nested capabilities
/// included. Built once per interned definition.
/proc/activation_plan(datum/capability/def)
	var/static/list/plans = list()
	var/list/plan = plans[def]
	if(!isnull(plan))
		return plan
	var/datum/type_table/scratch = new
	scratch.owner_type = def.type
	scratch.items = list()
	scratch.caps = list()
	table_add_capability(scratch, def, "[def.type]", null, null)
	plan = list()
	for(var/datum/centry/C as anything in scratch.items)
		if(C.item != def)
			plan += C
	plans[def] = plan
	return plan

/// Engines validate without an activation: adapter so `validate` can be written with or without one.
/datum/entry_engine/proc/validate_for(datum/activation/A, datum/entry/E)
	return validate(A, E)

/// The activation of (holder, key) from `source`, or null.
/proc/activation_find(datum/holder, key, source)
	var/datum/rx_state/rx = holder.rx
	if(!rx)
		return null
	for(var/datum/activation/A as anything in rx.activations)
		if(A.def.key == key && A.source == source && !A.dead)
			return A
	return null

/// The live activations of capability `key` (a definition key) on holder, in attach order.
/proc/activations_of(datum/holder, key)
	. = list()
	var/datum/rx_state/rx = holder.rx
	for(var/datum/activation/A as anything in rx?.activations)
		if(A.def.key == key && !A.dead)
			. += A

/// The live activations of capability id `cap_id` (any selector) on holder, in attach order.
/proc/activations_of_cap(datum/holder, cap_id)
	. = list()
	var/datum/rx_state/rx = holder.rx
	for(var/datum/activation/A as anything in rx?.activations)
		if(A.def.cap_id == cap_id && !A.dead)
			. += A

/// The hook of a capability that has code of its own: runs when the activation attaches.
/datum/capability/proc/on_activate(datum/activation/A)
	return

/// The cleanup hook of the one teardown path: runs after the contributions are removed and before the record drops.
/datum/capability/proc/on_deactivate(datum/activation/A)
	return

/proc/activation_expire(datum/activation/A)
	if(!A || A.dead)
		return
	activation_end(A)

// ---- revoke, read ----

/// Ends `source`'s activation of `what` on holder at once: it is dead when this returns. TRUE when there was one.
/proc/revoke(datum/holder, what, source)
	var/cap_id = grant_cap_id(what)
	if(isnull(cap_id))
		return legacy_revoke(holder, what, isnull(source) ? "grant" : source)
	if(!isdatum(holder))
		return FALSE
	var/datum/capability/def = grant_definition(what)
	var/found = FALSE
	for(var/datum/activation/A as anything in holder.rx?.activations?.Copy())
		if(A.dead || A.source != source || A.def.cap_id != cap_id)
			continue
		if(istype(what, /datum/capability) && A.def.key != def.key)
			continue
		activation_end(A)
		found = TRUE
	return found

/// TRUE while `what` is granted to `holder` by any source, or the holder's own type declares it.
/proc/granted(datum/holder, what)
	var/cap_id = grant_cap_id(what)
	if(isnull(cap_id))
		return legacy_granted(holder, what)
	if(!isdatum(holder) || QDELETED(holder))
		return FALSE
	var/key = null
	if(istype(what, /datum/capability))
		var/datum/capability/what_def = what
		key = what_def.key
	for(var/datum/activation/A as anything in holder.rx?.activations)
		if(A.dead || A.def.cap_id != cap_id)
			continue
		if(key && A.def.key != key)
			continue
		return TRUE
	var/datum/type_table/T = table_of(holder)
	for(var/table_key in T.caps)
		var/datum/capability/type_def = T.caps[table_key]
		if(type_def.cap_id == cap_id && (!key || type_def.key == key))
			return TRUE
	return FALSE

/// The capability of `E` with id `cap_id` (and selector): the interned definition of its type-level or a live granted activation,
/// null when it has none. With one instance of the capability the selector may be left out. Replaces the legacy cap_of(atom, key).
/proc/cap_of(datum/E, key, selector)
	READS_FROM() // the type's compiled table, not an entity's state
	if(!isnum(key))
		return capability_lookup(E, key)
	var/datum/type_table/T = table_of(E)
	var/list/found = table_cap_defs(T, key, selector)
	if(length(found))
		return found[1]
	for(var/datum/activation/A as anything in E.rx?.activations)
		if(!A.dead && A.def.cap_id == key && (isnull(selector) || A.def.selector == selector))
			return A.def
	return null

// ---- stacking ----

/// Recomputes which activations of capability `key` on holder run (section 11 "stacks ="). A type-level capability of the same key
/// takes part as the first activation, made lazily only now that something else stacks with it.
/proc/activation_restack(datum/holder, key)
	var/list/set_of = activations_of(holder, key)
	if(!length(set_of))
		return
	var/datum/type_table/T = table_of(holder)
	var/datum/capability/type_def = T.caps[key]
	if(type_def && !activation_find(holder, key, holder) && length(set_of))
		var/datum/activation/base = activation_attach(holder, type_def, holder, null, SCOPE_TYPE, null, null)
		if(base)
			return // the attach restacked
	var/datum/activation/first_activation = set_of[1]
	var/list/stacks = cap_stacks(first_activation.def)
	switch(stacks[1])
		if(STACKS_UNIQUE)
			var/first = TRUE
			for(var/datum/activation/A as anything in set_of)
				A.runs = first
				first = FALSE
		if(STACKS_BEST)
			var/param = stacks[2]
			var/datum/activation/best = null
			var/best_value = null
			for(var/datum/activation/A as anything in set_of)
				var/value = cap_param(A.def, param)
				if(isnull(best) || value > best_value)
					best = A
					best_value = value
			for(var/datum/activation/A as anything in set_of)
				A.runs = (A == best)
		else
			for(var/datum/activation/A as anything in set_of)
				A.runs = TRUE

/// The activations of `cap_id` (and selector) on holder whose behaviour runs, in attach order. One for UNIQUE and BEST.
/proc/running_activations(datum/holder, cap_id, selector)
	. = list()
	for(var/datum/activation/A as anything in activations_of_cap(holder, cap_id))
		if(A.runs && (isnull(selector) || A.def.selector == selector))
			. += A

/// The winning activation of a BEST or UNIQUE capability (the first running one), or null.
/proc/winning_activation(datum/holder, cap_id, selector)
	RETURN_TYPE(/datum/activation)
	var/list/running = running_activations(holder, cap_id, selector)
	return length(running) ? running[1] : null

// ---- the one teardown path ----

/**
 * Ends activation A: marks it dead at once, then, in this order, ends the activations it owns, removes its contributions, runs its
 * on_deactivate and drops its record. It may be called from inside one of A's own handlers: that handler finishes, nothing of A
 * runs again.
 */
/proc/activation_end(datum/activation/A)
	if(!A || A.dead)
		return FALSE
	OP_PURE_GUARD("[A.def?.key] was revoked from [A.holder?.type]")
	A.dead = TRUE
	A.runs = FALSE
	var/datum/capability/def = A.def
	var/datum/holder = A.holder
	// 1. end what it owns
	for(var/datum/activation/child as anything in A.owned?.Copy())
		activation_end(child)
	A.owned = null
	// 2. remove its contributions (the stats recompute inline)
	for(var/list/pair as anything in A.applied)
		var/datum/entry_engine/engine = pair[2]
		engine.remove(A, pair[1])
	A.applied = null
	// 3. on_deactivate
	def.on_deactivate(A)
	// 4. drop the record
	if(holder?.rx)
		LAZYREMOVE(holder.rx.activations, A)
	if(isdatum(A.source))
		var/datum/source_datum = A.source
		if(source_datum.rx)
			LAZYREMOVE(source_datum.rx.sourced, A)
	if(A.parent)
		LAZYREMOVE(A.parent.owned, A)
	if(A.lasts && holder && !QDELETED(holder))
		cancel_after(holder, "activation:[A.serial]")
	TEST_REC_ACTIVATION(TEST_EVENT_DETACH, def, A.source, holder)
	if(holder && !QDELETED(holder))
		activation_restack(holder, def.key)
	A.data = null // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	return TRUE

/// The destroy transaction's call for a dying datum: every activation it carries as a holder and every one it sourced ends.
/proc/activations_teardown(datum/D)
	var/datum/rx_state/rx = D.rx
	if(!rx)
		return
	for(var/datum/activation/A as anything in rx.activations?.Copy())
		activation_end(A)
	for(var/datum/activation/A as anything in rx.sourced?.Copy())
		activation_end(A)
	rx.activations = null
	rx.sourced = null
	rx.rel_scopes = null

// ---- state: capability keys and typed data ----

/// The typed per-activation data of A, made on first use (the capability's data type, section 11). The legacy form
/// cap_data(holder, capability) of the datum capabilities keeps working: a first argument that is no activation is that call.
/proc/cap_data(datum/A, datum/capability/C)
	RETURN_TYPE(/datum)
	if(!istype(A, /datum/activation))
		return capability_instance_data(A, C)
	var/datum/activation/act = A
	return activation_data(act)

/proc/activation_data(datum/activation/A)
	RETURN_TYPE(/datum/cap_data)
	if(!A.data)
		var/data_type = A.def.cap_data_type()
		if(data_type)
			A.data = new data_type // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	return A.data

/// The type of /datum/cap_data this capability's activations carry, or null.
/datum/capability/proc/cap_data_type()
	return null

/// Sets state key `key_id` in activation A (a granted capability's own handlers reach their state this way). TRUE when it changed.
/proc/cap_key_set_in(datum/activation/A, key_id, value)
	var/bit = 1 << (CAPKEY_BIT(key_id) - 1)
	var/was = !!(A.state & bit)
	if(was == !!value)
		return FALSE
	if(value)
		A.state |= bit
	else
		A.state &= ~bit
	TEST_REC_DELTA(A.holder, "cap_key:[key_id]", was, !!value)
	capability_key_changed(A.holder, key_id)
	return TRUE

/// TRUE when state key `key_id` is set in activation A.
/proc/cap_key_get_in(datum/activation/A, key_id)
	return !!(A.state & (1 << (CAPKEY_BIT(key_id) - 1)))

/// The type-level (or only) activation of `cap_id` on holder, created lazily: the one whose state the accessors read and write.
/proc/cap_activation(datum/holder, cap_id, selector, create = FALSE)
	READS_FROM(holder)
	var/datum/capability/def = cap_of(holder, cap_id, selector)
	if(!def)
		return null
	var/datum/activation/A = activation_find(holder, def.key, holder)
	if(A || !create)
		return A
	return activation_attach(holder, def, holder, null, SCOPE_TYPE, null, null)

/// TRUE when state key `key_id` (CAPKEY_ID) of the type-level activation is set.
/proc/cap_key_get(datum/holder, key_id, selector)
	var/datum/activation/A = cap_activation(holder, CAPKEY_CAP(key_id), selector, FALSE)
	if(!A)
		return FALSE
	return !!(A.state & (1 << (CAPKEY_BIT(key_id) - 1)))

/// Sets state key `key_id` of the holder's capability (the one capability of that id: no selector). TRUE when it changed. The everyday form of
/// cap_key_set().
/proc/key_set(datum/holder, key_id, value)
	return cap_key_set(holder, key_id, value, null)

/// Sets state key `key_id` of the holder's type-level activation (the activation is made now if it did not exist). Publishes the
/// key on the holder when it changed. TRUE when it changed.
/proc/cap_key_set(datum/holder, key_id, value, selector)
	var/datum/activation/A = cap_activation(holder, CAPKEY_CAP(key_id), selector, TRUE)
	if(!A)
		declare_report("cap_key_set on [holder.type]: it has no capability [CAPKEY_CAP(key_id)]")
		return FALSE
	var/bit = 1 << (CAPKEY_BIT(key_id) - 1)
	var/was = !!(A.state & bit)
	if(was == !!value)
		return FALSE
	if(value)
		A.state |= bit
	else
		A.state &= ~bit
	TEST_REC_DELTA(holder, "cap_key:[key_id]", was, !!value)
	capability_key_changed(holder, key_id)
	return TRUE

/// A capability key changed on holder: published to whatever reads it. E3's inline recompute and E4's change hooks read it from here.
/proc/capability_key_changed(datum/holder, key_id)
	engine_key_changed(holder, "capkey:[key_id]")
	// A capability's state is drawn, examined and shown in windows: every output of the holder re-derives (the legacy cap_set() raised the same channel).
	state_changed(holder, CHANGE_CAPABILITY)

/// Something an engine may depend on changed on `holder` under `key` (a tracked var name, "capkey:<id>", a stat id): published to the
/// readers of the key. E3 extends this with the inline recompute of the stats that read it.
/proc/engine_key_changed(datum/holder, key)
	OP_PURE_GUARD("[key] of [holder?.type] was published")
	// The stat layer: a stat that reads this key (a gated contribution's condition, a capability key) is right before the writer's next line.
	if(GLOB.stat_input_keys?[key] && key != GLOB.stat_writing)
		stat_inputs_changed(holder, key)
	op_changed(holder)
	if(READERS(holder, key))
		publish_change(holder, key)

// ---- explain ----

/// Every activation on `E` with its source, scope and contributions, one line each (the admin verb "List Activations").
/proc/explain_activations(datum/E)
	var/list/lines = list()
	var/datum/type_table/T = table_of(E)
	for(var/key in T.caps)
		var/datum/capability/def = T.caps[key]
		lines += "[activation_def_text(def)]  source type [E.type]  scope type-level"
	for(var/datum/activation/A as anything in E.rx?.activations)
		lines += activation_line(A)
	return jointext(lines, "\n")

/proc/activation_def_text(datum/capability/def)
	return "[capability_label(def)][def.selector ? " \"[def.selector]\"" : ""]"

/proc/activation_line(datum/activation/A)
	var/scope_text
	switch(A.scope)
		if(SCOPE_SOURCE)
			scope_text = "while source exists[A.lasts ? ", for [A.lasts / 10]s" : ""]"
		if(SCOPE_SLOT)
			scope_text = "while slotted ([A.scope_data])"
		if(SCOPE_COND)
			scope_text = "while condition holds"
		if(SCOPE_RELATION)
			scope_text = "while relation [A.scope_data] names it"
		if(SCOPE_TYPE)
			scope_text = "type-level"
	var/source_text = "SRC [A.source]"
	if(isdatum(A.source))
		var/datum/source_datum = A.source
		source_text = "[source_datum.type]"
	var/cap = A.def.cap_id ? A.def : null
	var/stack_text = ""
	if(A.def.cap_id)
		var/list/stacks = cap_stacks(A.def)
		if(stacks[1] != STACKS_STACK)
			stack_text = "  stacks [stacks[1]]: [A.runs ? "winning" : "shadowed"]"
	return "[activation_def_text(A.def)]  source [source_text]  scope [scope_text][stack_text][A.dead ? "  (dead)" : ""][cap && A.applied ? "  contributes [length(A.applied)]" : ""]"
