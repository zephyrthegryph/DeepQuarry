// Lazy owned state (the storage contract; owns_one(lazy = TRUE) and lazy_state()).
//
// State that only a few instances ever hold is not a var on the base type and not a slot in a text-keyed table: it is the vars of a small state
// datum, made when the first instance needs it. There are two forms, chosen by the holder:
//
// Var form (mobs): the holder owns the datum in a var.
//
//	/datum/burn_state
//		var/fuel = 0
//
//	CAPABILITIES(/mob/living)
//		owns_one(nameof(burn), /datum/burn_state, lazy = TRUE)
//
//	STATE_GET(A, burn, fuel)       read: the field, or the state type's own default while no state exists; a read allocates nothing
//	STATE_SET(A, burn, fuel, 5)    write (generated burn_write(); a null is the default): makes the datum on a non-default value, does nothing for a default value when there is
//	                               no datum, and drops the datum when its last non-default field returns to the default
//	burn_of(A).set_fuel(5)         the raw form: makes the datum, writes through the setter
//	burn_clear(A)                  the feature ended: the datum goes
//
// The datum is owned (rel_set), so it dies with its holder and needs no collection. Its vars are tracked like any other var: a write publishes the
// var's key on the state datum and on the holder's `burn` key, so a draw, stat or on_change that reads through that var follows it.
//
// Table form (atoms, movables, objects, items: types with millions of instances that may not carry a var): no var is declared. The state is a row of an
// engine table keyed by the holder's slot (code/engine/refs/slots.dm).
//
//	/datum/burn_state
//		parent_type = /datum/lazy_state
//		var/fuel = 0
//
//	CAPABILITIES(/obj/item)
//		lazy_state(burn, /datum/burn_state)
//
//	STATE_PEEK(A, burn, fuel)      read: the field, or the state type's default while the holder has no row
//	STATE_SET(A, burn, fuel, 5)    write, as above
//
// engine_forget() drops a destroyed holder's rows (lazy_state_forget), so these states need no collection either. A table-form read is not subscribed by a
// draw (there is no var to hop through); a look that must follow such a state reads it as a hop.

/// The value kind of a weak reference field in View Variables.
#define LAZY_KIND_WEAK "weak"

GLOBAL_VAR_INIT(lazy_states_made, 0)
GLOBAL_VAR_INIT(lazy_states_cleared, 0)
GLOBAL_VAR_INIT(lazy_state_published, 0)

/// The base of the state datums of table-form holders.
/datum/lazy_state
	/// The slot of the holder this state belongs to.
	var/tmp/lazy_holder_slot = 0
	/// The feature (the table) it lives in.
	var/tmp/lazy_feature

SCHEMA(/datum/lazy_state, lazy_holder_slot, num())
SCHEMA(/datum/lazy_state, lazy_feature, schema_text())

/// Makes the lazy state datum `var_name` of `holder` (a `state_type`), owned by it. Called by the generated `x_of()` when the var is still null.
/proc/lazy_state_make(datum/holder, var_name, state_type)
	if(!holder)
		stack_trace("lazy_state_make(): no holder for [var_name]")
		return null
	var/datum/state = new state_type
	if(QDELETED(holder))
		// A write during the holder's teardown: the caller still needs something to write to, and nothing should keep it. The state is not owned by
		// anything, so it is freed when the caller lets go of it.
		log_world("LAZY STATE: [holder.type].[var_name] written while its holder is being deleted; the state is discarded")
		return state
	rel_set(holder, var_name, state)
	GLOB.lazy_states_made++
	BOOT_PHASE_COUNT("lazy state: made on first write")
	return state

/// Ends a feature's state on `holder` (x_clear(A), generated): the datum is deleted and the var reads null again, so the next read gives the type's defaults.
/proc/lazy_state_clear(datum/holder, var_name)
	if(holder && !isnull(holder.vars[var_name]))
		rel_set(holder, var_name, null)
		GLOB.lazy_states_cleared++

/// A tracked var of lazy state S changed (TRACKED_STATE): published on S (an owned state), and on the holder as a change of the key that names S (the owned var, or the
/// feature of a table row), so whatever reads through it (a draw, a stat, an on_change) follows the write.
/proc/lazy_state_changed(datum/S, field)
	var/datum/holder
	var/slot_name
	var/datum/lazy_state/row = S
	if(istype(row) && row.lazy_holder_slot)
		// Table form: the holder is named by its slot. Nothing reads a row datum itself (a reader of the state follows the holder's feature key), and
		// publishing on it would give it a slot of its own, which a row dropped without qdel() would leave behind in the slot table.
		holder = slot_datum(row.lazy_holder_slot)
		slot_name = row.lazy_feature
	else
		tracked_changed(S, field)
		holder = owner_of(S)
		slot_name = S.own_slot
	if(holder && slot_name)
		tracked_changed(holder, slot_name)
		GLOB.lazy_state_published++

// ---- Table form ---------------------------------------------------------------------------------------------------------------------------

/// feature -> (slot -> state): one alist per feature, made with its first state.
GLOBAL_LIST_EMPTY(lazy_state_tables)

/// The state of `feature` that `H` holds, or null. Never gives the holder a slot.
/proc/lazy_state_peek(datum/H, feature)
	var/slot = slot_known(H)
	if(!slot)
		return null
	var/alist/rows = GLOB.lazy_state_tables[feature]
	return rows?[slot]

/// Field `field` of the holder's `feature` state, or `default` while it has none.
/proc/lazy_state_get(datum/H, feature, field, default)
	var/datum/S = lazy_state_peek(H, feature)
	return S ? S.vars[field] : default

/// Makes the holder's `feature` state (a `state_type`), in the table.
/proc/lazy_table_make(datum/holder, feature, state_type)
	if(!holder)
		stack_trace("lazy_table_make(): no holder for [feature]")
		return null
	var/datum/lazy_state/S = new state_type
	if(QDELETED(holder))
		log_world("LAZY STATE: [holder.type].[feature] written while its holder is being deleted; the state is discarded")
		return S
	var/slot = slot_of(holder)
	var/alist/rows = GLOB.lazy_state_tables[feature]
	if(!rows)
		rows = alist()
		GLOB.lazy_state_tables[feature] = rows
	S.lazy_holder_slot = slot
	S.lazy_feature = feature
	rows[slot] = S
	GLOB.lazy_states_made++
	BOOT_PHASE_COUNT("lazy state: made on first write")
	return S

/// Ends the holder's `feature` state (x_clear): the row goes and the state is deleted.
/proc/lazy_table_clear(datum/holder, feature)
	var/datum/S = lazy_state_peek(holder, feature)
	if(!S)
		return
	var/alist/rows = GLOB.lazy_state_tables[feature]
	rows -= slot_known(holder) // the row was the state's only reference and it names no slot of its own: BYOND frees it
	GLOB.lazy_states_cleared++

/// engine_forget(): a destroyed holder leaves every table.
/proc/lazy_state_forget(datum/D)
	var/slot = slot_known(D)
	if(!slot || !length(GLOB.lazy_state_tables))
		return
	for(var/feature in GLOB.lazy_state_tables)
		var/alist/rows = GLOB.lazy_state_tables[feature]
		var/datum/S = rows[slot]
		if(S)
			rows -= slot

// ---- Writes --------------------------------------------------------------------------------------------------------------------------------

GLOBAL_LIST_EMPTY(lazy_state_default_rows)

/// The shared read-only row of `feature` at its type's defaults: what x_view() answers while a holder has no state. Never written.
/proc/lazy_state_default_row(feature, state_type)
	var/datum/row = handle_get(GLOB.lazy_state_default_rows[feature]) // kept by its slot; the table names it by handle
	if(!row)
		row = new state_type
		GLOB.lazy_state_default_rows[feature] = handle_of(row)
	return row

GLOBAL_LIST_EMPTY(lazy_state_base_name_set)
GLOBAL_LIST_EMPTY(lazy_state_defaults_by_type)
GLOBAL_LIST_EMPTY(lazy_state_weak_fields_by_type)

/// Whether field `field` of state type `state_type` is a weak reference (ref_one(weak = TRUE): the field has an accessor of its own name).
/proc/lazy_field_is_weak(state_type, field)
	lazy_state_defaults(state_type)
	return field in GLOB.lazy_state_weak_fields_by_type["[state_type]"]

/// The var names every state datum has apart from its own fields.
/proc/lazy_state_base_names()
	if(!length(GLOB.lazy_state_base_name_set))
		GLOB.lazy_state_base_name_set["lazy_holder_slot"] = TRUE
		GLOB.lazy_state_base_name_set["lazy_feature"] = TRUE
		var/datum/plain = new // read for its var names and let go: nothing holds it
		for(var/name in plain.vars)
			GLOB.lazy_state_base_name_set[name] = TRUE
	return GLOB.lazy_state_base_name_set

/// The fields of the state type `state_type` and what each is when unset: list(field = default, ...). Cached.
/proc/lazy_state_defaults(state_type)
	var/list/defaults = GLOB.lazy_state_defaults_by_type["[state_type]"]
	if(defaults)
		return defaults
	defaults = list()
	var/list/base_names = lazy_state_base_names()
	var/datum/proto = new state_type // read for its defaults and let go: nothing holds it
	var/list/weak = list()
	for(var/name in proto.vars)
		if(!base_names[name])
			defaults[name] = proto.vars[name]
			if(hascall(proto, name))
				weak += name
	GLOB.lazy_state_weak_fields_by_type["[state_type]"] = weak
	GLOB.lazy_state_defaults_by_type["[state_type]"] = defaults
	return defaults

/// Whether every field of state `S` is at its type's default (the state can go).
/proc/lazy_state_all_default(datum/S)
	var/list/base_names = lazy_state_base_names()
	for(var/name in S.vars)
		if(base_names[name])
			continue
		var/value = S.vars[name]
		var/default = initial(S.vars[name])
		if(value != default || isnull(value) != isnull(default))
			return FALSE
	return TRUE

// ---- By name (View Variables, SDQL, the state serializer) ---------------------------------------------------------------------------------

/// The lazy features `D` can hold: list(list(holder type, feature, state type, "table" or "var", write proc, clear proc), ...).
/proc/lazy_rows_of(datum/D)
	var/list/out = list()
	if(!isdatum(D))
		return out
	for(var/list/row as anything in lazy_feature_rows())
		if(istype(D, row[1]))
			out += list(row)
	return out

/// The feature row of `D` that has a field `field`, or null.
/proc/lazy_row_of_field(datum/D, field)
	for(var/list/row as anything in lazy_rows_of(D))
		if(field in lazy_state_defaults(row[3]))
			return row
	return null

/// The state `row` names on `D`, or null while it has none.
/proc/lazy_row_peek(datum/D, list/row)
	if(row[4] == "table")
		return lazy_state_peek(D, row[2])
	return D.vars[row[2]]

/// Field `field` of the state `row` names on `D`: its value, or the type's default while there is no state.
/proc/lazy_field_read(datum/D, list/row, field)
	var/datum/S = lazy_row_peek(D, row)
	if(S && hascall(S, field))
		return call(S, field)() // a weak reference field: the datum it names
	return S ? S.vars[field] : lazy_state_defaults(row[3])[field]

/// Writes field `field` of the state `row` names on `D` (null is the default), through the feature's write proc: no state is made for a default value.
/proc/lazy_field_write(datum/D, list/row, field, value)
	var/default = lazy_state_defaults(row[3])[field]
	if(lazy_field_is_weak(row[3], field))
		call(row[7])(D, field, value) // a weak reference field
		return
	if(isnull(value))
		value = default
	call(row[5])(D, value, default, "set_[field]")

/// Whether a lazy field's value is plain data the state serializer can keep (a number, text, path or list): not a datum, image or particle set.
/proc/lazy_value_saveable(value)
	return isnull(value) || isnum(value) || istext(value) || ispath(value) || islist(value)

/// Every non-default plain field of `D`'s lazy states, for the state serializer: list("feature.field" = value, ...).
/proc/lazy_state_saved(datum/D)
	var/list/out
	for(var/list/row as anything in lazy_rows_of(D))
		var/datum/S = lazy_row_peek(D, row)
		if(!S)
			continue
		var/list/defaults = lazy_state_defaults(row[3])
		for(var/field in defaults)
			var/value = S.vars[field]
			if(value == defaults[field] && isnull(value) == isnull(defaults[field]))
				continue
			if(!lazy_value_saveable(value) || hascall(S, field))
				continue // a datum, or a weak reference (the field of the same name is its accessor): runtime only
			out = out || list()
			out["[row[2]].[field]"] = value
	return out

/// Restores what lazy_state_saved() wrote: every plain field is reset to its default (runtime-only fields, an image or a particle set, are left), then the saved fields are written back.
/proc/lazy_state_restore(datum/D, list/saved)
	for(var/list/row as anything in lazy_rows_of(D))
		var/datum/S = lazy_row_peek(D, row)
		if(!S)
			continue
		var/list/defaults = lazy_state_defaults(row[3])
		for(var/field in defaults)
			if(lazy_value_saveable(S.vars[field]) && !hascall(S, field))
				lazy_field_write(D, row, field, defaults[field])
	for(var/key in saved)
		var/dot = findtext(key, ".")
		var/feature = copytext(key, 1, dot)
		var/field = copytext(key, dot + 1)
		for(var/list/row as anything in lazy_rows_of(D))
			if(row[2] == feature)
				lazy_field_write(D, row, field, saved[key])
				break
