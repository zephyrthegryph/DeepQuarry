// Scopes of an activation (doc/rewrite/final_api.html, section 5 "Scoped activation (X1)"; section 11 "Mobs", section 6 "Order for one
// instance"). An activation's scope says what ends it besides revoke(): its source (the default), the time an item spends in a slot,
// a condition, or a relation naming a value (a species change is a relation write, and an edge of the graph). Nothing polls: a scope
// changes when the write that changes it runs.

/// The engine's work on a holder when it initializes (capability hooks, relation-scoped grants of the value a relation starts with).
/// Called from the lifecycle's init step for a type whose table has any (own_table.engine_init).
/proc/engine_holder_init(datum/holder, mapload)
	var/datum/type_table/T = table_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_CAPABILITY))
		var/datum/capability/def = C.item
		if(def.holder_hooks & HOLDER_HOOK_INIT)
			def.run_holder_hook(holder, mapload, HOLDER_HOOK_INIT)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_REL_GRANTS))
		var/datum/entry/E = C.item
		activations_relation_changed(holder, E.args["var"], TRUE)
	if(T.hook_flags & ENGINE_HOOK_STATS)
		stat_holder_init(holder, mapload)
	hooks_change_baseline(holder)
	type_every_arm(holder, T)

/// Before the base body of Initialize runs: for work the parent's init reads (a part made in nullspace).
/proc/engine_holder_preinit(datum/holder, mapload)
	var/datum/type_table/T = table_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_CAPABILITY))
		var/datum/capability/def = C.item
		if(def.holder_hooks & HOLDER_HOOK_PREINIT)
			def.run_holder_hook(holder, mapload, HOLDER_HOOK_PREINIT)

/// The destroy transaction: on_holder_destroy of each capability, then every activation ends (activations_teardown).
/proc/engine_holder_destroy(datum/holder)
	if(!islist(GLOB?.type_table_of_type))
		return
	var/datum/type_table/T = GLOB.type_table_of_type[holder.type]
	if(!T)
		return
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_CAPABILITY))
		var/datum/capability/def = C.item
		if(def.holder_hooks & HOLDER_HOOK_DESTROY)
			def.run_holder_hook(holder, FALSE, HOLDER_HOOK_DESTROY)


/// Runs the capability's lifecycle hook for holder with a reused evaluation context (A.holder and A.cap set, A.mapload while the
/// map loads).
/datum/capability/proc/run_holder_hook(datum/holder, mapload, which)
	var/datum/act/eval/A = take(/datum/act/eval)
	A.holder = holder // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	A.cap = src
	A.mapload = mapload
	switch(which)
		if(HOLDER_HOOK_PREINIT)
			on_holder_preinit(A)
		if(HOLDER_HOOK_INIT)
			on_holder_init_ctx(A)
		if(HOLDER_HOOK_DESTROY)
			on_holder_destroy_ctx(A)
	A.release()

/datum/act/eval
	/// TRUE while the map loads (capability init hooks).
	var/mapload = FALSE

/datum/capability
	/// HOLDER_HOOK_* bits: which of the lifecycle hooks below this definition overrides (the lifecycle skips the capability otherwise).
	var/holder_hooks = 0

/// The hooks of a capability with code of its own, all x(datum/act/A) with A.holder and A.cap set: `on_holder_preinit` runs before the
/// parent type's init code reads the holder, `on_holder_init_ctx` after the capability is initialized, `on_holder_destroy_ctx` first in the
/// destroy transaction. (The legacy on_holder_init(holder, mapload) of the datum form is a different proc and stays.)
/datum/capability/proc/on_holder_preinit(datum/act/eval/A)
	return

/datum/capability/proc/on_holder_init_ctx(datum/act/eval/A)
	return

/datum/capability/proc/on_holder_destroy_ctx(datum/act/eval/A)
	return

// ---- relation scope: species_capabilities() ----

/// The entry kinds of a relation-granted value's own list that work on the holder (relation_scope_capabilities()).
GLOBAL_LIST_INIT(relation_scope_kinds, list(ENTRY_PROVIDES, "contributes", ENTRY_EXTEND, ENTRY_ON_NOTICE, ENTRY_ON_CHANGE, "every"))

/**
 * holder.var_name (a relation) was written. The grants it drives, rel_grants(nameof(var)) entries of the holder's table, are re-made:
 * what the old value granted ends, then each capability the new value's own CAPABILITIES list declares is granted, sourced by the new
 * value and scoped to the relation. A species change is therefore a relation write, and everything the old species gave goes in the
 * same step.
 */
/proc/activations_relation_changed(datum/holder, var_name, init = FALSE)
	if(!holder || (QDELETED(holder) && !init) || !islist(GLOB?.type_table_of_type))
		return
	var/datum/type_table/T = GLOB.type_table_of_type[holder.type]
	if(!T)
		if(!init)
			return
		T = table_of(holder)
	if(!T.rel_grant_vars || !(var_name in T.rel_grant_vars))
		return
	var/datum/rx_state/rx = rx_of(holder)
	// End the grants the previous value made.
	for(var/datum/activation/A as anything in rx.activations?.Copy())
		if(A.scope == SCOPE_RELATION && A.scope_data == var_name)
			activation_end(A)
	var/datum/value = holder.vars[var_name]
	if(!isdatum(value) || QDELETED(value))
		return
	for(var/datum/capability/def as anything in relation_scope_capabilities(value))
		activation_attach(holder, def, value, null, SCOPE_RELATION, var_name, null)
	log_world("GRANTS: [holder.type] now gets what [value.type] declares through [var_name]")

/// What a value granted through a relation (a species) brings its holder: each capability its own CAPABILITIES list names, and every other entry
/// that works on a holder (a provider such as hands(), a contribution, a hook, an every()) together in one capability of triggers only, so the
/// relation scopes them like any grant and one teardown path ends them. An entry inside a when() keeps its condition. Built once per value type.
/proc/relation_scope_capabilities(datum/value)
	var/static/list/known = list()
	var/list/cached = known[value.type]
	if(!isnull(cached))
		return cached
	var/datum/type_table/value_table = table_of(value)
	. = list()
	var/list/loose = list()
	for(var/datum/centry/C as anything in value_table.items)
		if(istype(C.item, /datum/capability))
			if(isnull(C.owner))
				. += C.item
			continue
		var/datum/entry/E = C.item
		if(!istype(E) || !isnull(C.owner) || !(E.kind in GLOB.relation_scope_kinds))
			continue
		var/datum/entry/wrapped = E
		for(var/i in length(C.whens) to 1 step -1)
			var/datum/entry/W = C.whens[i]
			wrapped = entry_make(ENTRY_WHEN, null, W.args, list(wrapped))
		loose += wrapped
	if(length(loose))
		. += hook_capability_of(loose, FALSE)
	known[value.type] = .

// ---- slot scope: while_slotted() ----

/// `item` was put into `holder`'s slot `slot_id` (the ledger's note_enter() and reslot() call this for every real slot move). The while_slotted
/// entries of the item's type (ON_HOLDER) are granted to the holder with the item as source, and those of the holder's type (ON_CONTENTS) to the
/// item with the holder as source, both for exactly the item's time in the slot and bound to it. A type with no while_slotted entry costs two
/// flag reads.
/proc/activations_slot_enter(datum/item, datum/holder, slot_id)
	if(!islist(GLOB?.type_table_of_type) || QDELETED(item) || QDELETED(holder))
		return
	var/datum/type_table/item_table = table_of(item)
	if(item_table.has_slotted)
		for(var/datum/centry/C as anything in compiled_entries(item_table, ENTRY_WHILE_SLOTTED))
			var/datum/entry/E = C.item
			if(E.args["on"] != ON_HOLDER || !slot_matches(E.args["slot"], slot_id, holder))
				continue
			for(var/datum/capability/child as anything in slot_scope_capabilities(E))
				activation_attach(holder, child, item, null, SCOPE_SLOT, slot_id, null)
	var/datum/type_table/holder_table = table_of(holder)
	if(holder_table.has_slotted)
		for(var/datum/centry/C as anything in compiled_entries(holder_table, ENTRY_WHILE_SLOTTED))
			var/datum/entry/E = C.item
			if(E.args["on"] != ON_CONTENTS || !slot_matches(E.args["slot"], slot_id, holder))
				continue
			for(var/datum/capability/child as anything in slot_scope_capabilities(E))
				activation_attach(item, child, holder, null, SCOPE_SLOT, slot_id, null)

/// `item` left `holder`'s slot `slot_id`, however it left: everything the slot scoped goes at once.
/proc/activations_slot_exit(datum/item, datum/holder, slot_id)
	if(!islist(GLOB?.type_table_of_type))
		return
	// Only what a while_slotted entry could have made is looked for: a type that declares none holds none.
	if(holder.rx?.activations && table_of(item).has_slotted)
		for(var/datum/activation/A as anything in holder.rx.activations.Copy())
			if(A.scope == SCOPE_SLOT && A.scope_data == slot_id && A.source == item)
				activation_end(A)
	if(item.rx?.activations && table_of(holder).has_slotted)
		for(var/datum/activation/A as anything in item.rx.activations.Copy())
			if(A.scope == SCOPE_SLOT && A.scope_data == slot_id && A.source == holder)
				activation_end(A)

/// Does a while_slotted entry's slot id cover the slot an item went into? An entry may name a family of slots (a list of ids), or SLOT_ANY_WORN
/// (any slot of the holder that is worn equipment) or SLOT_ANY_HELD (any hand).
/proc/slot_matches(entry_slot, slot_id, atom/holder)
	if(islist(entry_slot))
		return slot_id in entry_slot
	if(entry_slot == SLOT_ANY_WORN || entry_slot == SLOT_ANY_HELD)
		var/datum/om/relation/slot/def = holder?.ledger?.def_by_id(slot_id)
		if(!def)
			return FALSE
		if(entry_slot == SLOT_ANY_HELD)
			return istype(def, /datum/om/relation/slot/body/hand)
		var/datum/om/relation/slot/body/body_def = def
		return istype(body_def) && !!(body_def.roles & BODY_SLOT_WORN)
	return entry_slot == slot_id

/// The capabilities a while_slotted entry applies: each capability child as it is, and every other entry (a hook, a contribution) together in one
/// capability of triggers only (hook_capability()), so the slot scopes them like any grant and one teardown path ends them.
/proc/slot_scope_capabilities(datum/entry/E)
	. = list()
	var/list/loose = list()
	for(var/child in E.children)
		if(istype(child, /datum/capability))
			. += child
		else
			loose += child
	if(length(loose))
		. += hook_capability_of(loose, FALSE)
