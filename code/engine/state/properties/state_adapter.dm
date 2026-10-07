// The one coupling point between properties and the state schema (track L,
// doc/rewrite/state.md §2). Property values that come from saved state are
// read only through here, and here only through the schema API
// (code/datums/state/schema.dm).

/// Current value of saved var `var_name` on `D`, or null if it isn't part of D's saved state.
/proc/dq_property_state_value(datum/D, var_name)
	return state_is_saved(D, var_name) ? D.vars[var_name] : null

/// Whether `var_name` is part of `D`'s saved state.
/proc/dq_property_state_has_var(datum/D, var_name)
	return state_is_saved(D, var_name)

/// A type's default for list var `var_name`, which initial() cannot give.
/// Only latent-safe types answer (see state_type_list_default()); others are null.
/proc/dq_property_type_state_list(path, var_name)
	return state_type_list_default(path, var_name)

/// Variant key of instance `D`, or null.
/proc/dq_property_instance_variant(datum/D)
	return dq_property_state_value(D, "variant")

/// The variant overrides that apply to instance `D`, or null.
/proc/dq_property_instance_variant_vars(datum/D)
	return D.state_variant_baseline()
