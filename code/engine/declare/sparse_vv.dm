// Sparse slots in View Variables, mass edit and SDQL.
//
// A sparse slot is not a var, so `vars` does not list it. The slot declarations (sparse(), read by `analyze gen sparse_slots` into
// sparse_slot_rows()) are the registry: every slot a datum's type declares is listed in View Variables as `@slot.name` (set or at its default),
// edited by that name (or the bare slot name where no var has it) and written through _sparse_set(), the same writer the setters use. A null
// value, and Restore to Default, clear the slot.

/// The prefix of a slot's View Variables name.
#define SPARSE_SLOT_PREFIX "@slot."

/// The declaration rows `D`'s type carries: list(list(owner type, slot name, value kind), ...).
/proc/sparse_slot_rows_of(datum/D)
	var/list/out = list()
	if(!isdatum(D))
		return out
	for(var/list/row as anything in sparse_slot_rows())
		if(istype(D, row[1]))
			out += list(row)
	return out

/// The View Variables name of slot `slot`.
/proc/sparse_slot_label(slot)
	return "[SPARSE_SLOT_PREFIX][slot]"

/// Resolves a by-name access to a slot `D` declares: `@slot.name` (what View Variables lists), or the bare slot name where no var of D has it
/// (SDQL). The slot's name, or null.
/proc/sparse_slot_named(datum/D, name)
	if(!isdatum(D) || !istext(name))
		return null
	var/slot = name
	if(copytext(name, 1, length(SPARSE_SLOT_PREFIX) + 1) == SPARSE_SLOT_PREFIX)
		slot = copytext(name, length(SPARSE_SLOT_PREFIX) + 1)
	else if(name in D.vars)
		return null
	for(var/list/row as anything in sparse_slot_rows())
		if(row[2] == slot && istype(D, row[1]))
			return slot
	return null

/// The declaration row of slot `slot` on `D`, or null.
/proc/sparse_slot_row(datum/D, slot)
	for(var/list/row as anything in sparse_slot_rows())
		if(row[2] == slot && istype(D, row[1]))
			return row
	return null

/// Every slot `D` declares, for View Variables: list("@slot.name" = value or null, ...).
/proc/sparse_slots_of(datum/D)
	var/list/out = list()
	for(var/list/row as anything in sparse_slot_rows_of(D))
		out[sparse_slot_label(row[2])] = sparse_slot_value(D, row[2])
	return out

/// The value of slot `slot` of `D` as View Variables shows it: a weak slot (type = weak) answers the datum it names, any other its stored value.
/proc/sparse_slot_value(datum/D, slot)
	var/list/row = sparse_slot_row(D, slot)
	if(row && row[3] == SPARSE_KIND_WEAK)
		return _sparse_ref(D, slot)
	return _sparse_get(D, slot)

/// Writes slot `slot` of `D` through the sparse writer (null clears it). Returns TRUE.
/proc/sparse_slot_write(datum/D, slot, value)
	var/list/row = sparse_slot_row(D, slot)
	if(row && row[3] == SPARSE_KIND_WEAK)
		_sparse_ref_set(D, slot, value)
		return TRUE
	_sparse_set(D, slot, value)
	return TRUE

/// The value of var `name` of `D` as View Variables and mass edit show it: a slot's value, else the var.
/proc/vv_var_value(datum/D, name)
	if(!(name in D.vars))
		var/slot = sparse_slot_named(D, name)
		if(slot)
			return sparse_slot_value(D, slot)
		var/list/trait_field = type_trait_field_named(D, name)
		if(trait_field)
			return type_trait_of(D, trait_field[1]).vars[trait_field[2]]
	return D.vars[name]

/// What Restore to Default sets var `name` of `D` to: a slot is unset (null), a var its compiled default.
/proc/vv_var_default(datum/D, name)
	if(!(name in D.vars) && sparse_slot_named(D, name))
		return null
	if(!(name in D.vars))
		var/list/trait_field = type_trait_field_named(D, name)
		if(trait_field)
			return type_trait_of_type(D.type, trait_field[1]).vars[trait_field[2]]
	return initial(D.vars[name])

/// The View Variables editor class a slot of value kind `kind` opens on while it is unset.
/proc/sparse_slot_vv_class(kind)
	switch(kind)
		if("num", "bool")
			return VV_NUM
		if("text")
			return VV_TEXT
		if("color")
			return VV_COLOR
		if("list")
			return VV_LIST
		if("/image", SPARSE_KIND_WEAK)
			return VV_DATUM_REFERENCE
	return VV_NULL
