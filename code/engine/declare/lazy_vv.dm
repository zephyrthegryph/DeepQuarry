// Lazy state fields in View Variables, mass edit and SDQL.
//
// A field of a lazy state (code/engine/declare/lazy_state.dm) is not a var of its holder, so `vars` does not list it. The generated registry
// lazy_feature_rows() (every lazy_state() and owns_one(lazy = TRUE) declaration) says which states a datum's type can hold: each field of those is listed in
// View Variables as `@slot.name` (set or at its default), edited by that name (or the bare field name where no var has it), written through the feature's
// write proc (no state is made for a default value), and reset by a null value or Restore to Default.

/// The prefix of a field's View Variables name.
#define VV_SLOT_PREFIX "@slot."

/// The fields `D`'s type can hold in lazy states: list(list(holder type, field name, value kind), ...).
/proc/vv_slot_rows_of(datum/D)
	var/list/out = list()
	for(var/list/lazy as anything in lazy_rows_of(D))
		var/list/defaults = lazy_state_defaults(lazy[3])
		for(var/field in defaults)
			out += list(list(lazy[1], field, vv_slot_kind_of(lazy[3], field, defaults[field])))
	return out

/// The value kind a field of state type `state_type` with default `default` shows as.
/proc/vv_slot_kind_of(state_type, field, default)
	if(lazy_field_is_weak(state_type, field))
		return LAZY_KIND_WEAK
	if(isnum(default))
		return "num"
	if(istext(default))
		return "text"
	return ""

/// The View Variables name of field `slot`.
/proc/vv_slot_label(slot)
	return "[VV_SLOT_PREFIX][slot]"

/// Resolves a by-name access to a field `D` can hold: `@slot.name` (what View Variables lists), or the bare field name where no var of D has it
/// (SDQL). The field's name, or null.
/proc/vv_slot_named(datum/D, name)
	if(!isdatum(D) || !istext(name))
		return null
	var/slot = name
	if(copytext(name, 1, length(VV_SLOT_PREFIX) + 1) == VV_SLOT_PREFIX)
		slot = copytext(name, length(VV_SLOT_PREFIX) + 1)
	else if(name in D.vars)
		return null
	if(lazy_row_of_field(D, slot))
		return slot
	return null

/// The row of field `slot` on `D`, or null.
/proc/vv_slot_row(datum/D, slot)
	var/list/lazy = lazy_row_of_field(D, slot)
	if(lazy)
		return list(lazy[1], slot, vv_slot_kind_of(lazy[3], slot, lazy_state_defaults(lazy[3])[slot]))
	return null

/// Every field `D` can hold, for View Variables: list("@slot.name" = value or null, ...).
/proc/vv_slots_of(datum/D)
	var/list/out = list()
	for(var/list/row as anything in vv_slot_rows_of(D))
		out[vv_slot_label(row[2])] = vv_slot_value(D, row[2])
	return out

/// The value of field `slot` of `D` as View Variables shows it: a weak reference answers the datum it names, any other field its value or its default.
/proc/vv_slot_value(datum/D, slot)
	var/list/lazy = lazy_row_of_field(D, slot)
	return lazy ? lazy_field_read(D, lazy, slot) : null

/// Writes field `slot` of `D` through its feature's write proc (null resets it). Returns TRUE.
/proc/vv_slot_write(datum/D, slot, value)
	var/list/lazy = lazy_row_of_field(D, slot)
	if(lazy)
		lazy_field_write(D, lazy, slot, value)
	return TRUE

/// The value of var `name` of `D` as View Variables and mass edit show it: a field's value, else the var.
/proc/vv_var_value(datum/D, name)
	if(!(name in D.vars))
		var/slot = vv_slot_named(D, name)
		if(slot)
			return vv_slot_value(D, slot)
		var/list/trait_field = type_trait_field_named(D, name)
		if(trait_field)
			return type_trait_of(D, trait_field[1]).vars[trait_field[2]]
	return D.vars[name]

/// What Restore to Default sets var `name` of `D` to: a field its state type's default, a var its compiled default.
/proc/vv_var_default(datum/D, name)
	var/slot = !(name in D.vars) ? vv_slot_named(D, name) : null
	if(slot)
		var/list/lazy = lazy_row_of_field(D, slot)
		return lazy_state_defaults(lazy[3])[slot]
	if(!(name in D.vars))
		var/list/trait_field = type_trait_field_named(D, name)
		if(trait_field)
			return type_trait_of_type(D.type, trait_field[1]).vars[trait_field[2]]
	return initial(D.vars[name])

/// The View Variables editor class a field of value kind `kind` opens on while it is unset.
/proc/vv_slot_class(kind)
	switch(kind)
		if("num", "bool")
			return VV_NUM
		if("text")
			return VV_TEXT
		if(LAZY_KIND_WEAK)
			return VV_DATUM_REFERENCE
	return VV_NULL
