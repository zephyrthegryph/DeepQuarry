// The one coupling point between properties and the state schema (track L,
// doc/rewrite/state.md §2). Instance property values that come from saved
// state are read only through here.
//
// Until L1's schema lands this implements state.md's definition directly: the
// schema of a type is its saved vars (issaved() is false for tmp, const and
// global vars). When L1 lands, route these procs through its schema API.

/// Current value of saved var `var_name` on `D`, or null if it isn't part of D's saved state.
/proc/dq_property_state_value(datum/D, var_name)
	if(!(var_name in D.vars))
		return null
	if(!issaved(D.vars[var_name]))
		return null
	return D.vars[var_name]

/// Whether `var_name` is part of `D`'s saved state.
/proc/dq_property_state_has_var(datum/D, var_name)
	return (var_name in D.vars) && issaved(D.vars[var_name])

/// Variant key of instance `D`, or null.
/proc/dq_property_instance_variant(datum/D)
	if(!isitem(D))
		return null
	var/obj/item/I = D
	return I.variant

/// The variant overrides that apply to instance `D`, or null.
/proc/dq_property_instance_variant_vars(datum/D)
	var/key = dq_property_instance_variant(D)
	return isnull(key) ? null : dq_variant_vars(D.type, key)
