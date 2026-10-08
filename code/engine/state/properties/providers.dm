// Property providers (doc/rewrite/rules.md Â§1).
//
// Base providers answer for a type:
//   /datum/property_provider/type_var   an initial() var on the type, overridden
//                                       by the variant table and, per instance,
//                                       by saved state (state_adapter.dm).
//   /datum/property_provider/material   folded from the type's `matter` list
//                                       through the material registry.
// For a given type exactly one base provider answers a property: the one with
// the deepest `applies_to`. A deeper provider must name the one it replaces in
// `overrides`, or boot validation reports a conflict.
//
// Contributors fold into the base value through the property's aggregator:
//   /datum/property_provider/behaviour  a capability granted to the instance.
//   /datum/property_provider/equipment  a mob's equipped items.

/datum/property_provider
	/// Property id this provides.
	var/property
	/// PROP_SOURCE_*.
	var/source
	/// Root type this provider answers for.
	var/applies_to
	/// Unit of the values this provider returns. Must match the definition.
	var/unit
	/// Saved var the instance value is read from, through the state schema.
	var/state_var
	/// Provider types this one replaces for its (deeper) applies_to.
	var/list/overrides
	var/test_only = FALSE

/datum/property_provider/proc/is_base()
	return source == PROP_SOURCE_TYPE || source == PROP_SOURCE_MATERIAL || source == PROP_SOURCE_DOMAIN

/// Per-type value, without an instance. `variant_vars` is the variant's
/// var overrides, or null.
/datum/property_provider/proc/type_value(path, list/variant_vars)
	return null

/// Instance value. Defaults to the saved state var, else the type value.
/datum/property_provider/proc/instance_value(datum/D)
	if(state_var)
		return normalize(dq_property_state_value(D, state_var))
	return type_value(D.type, dq_property_instance_variant_vars(D))

/// A contributor's value for this instance, or null for none.
/datum/property_provider/proc/contribute(datum/D)
	return null

/// Generated rule tests: set this property's value on `D` to `value` the way
/// the game would. FALSE if this provider can't (the test then fails).
/datum/property_provider/proc/test_write(datum/D, value)
	return FALSE

/// Turns a raw var value into the property's value. Tags become TRUE/FALSE.
/datum/property_provider/proc/normalize(raw)
	return raw

// ---- Type vars ----

/datum/property_provider/type_var
	source = PROP_SOURCE_TYPE
	/// Key checked in the variant table; usually the same as state_var.
	var/variant_var

/datum/property_provider/type_var/type_value(path, list/variant_vars)
	if(variant_var && variant_vars && (variant_var in variant_vars))
		return normalize(variant_vars[variant_var])
	return normalize(read_initial(path))

/// Override with a typed initial() read, so the var name is checked at compile time.
/datum/property_provider/type_var/proc/read_initial(path)
	return null

/datum/property_provider/type_var/tag/normalize(raw)
	return raw ? TRUE : FALSE


GLOBAL_DATUM(property_environment, /datum/property_environment)
/datum/property_environment
/datum/property_environment/proc/variant_values(path, variant)
	return null

/datum/property_provider/behaviour
	source = PROP_SOURCE_BEHAVIOUR
	applies_to = /datum
	var/behaviour_type

/datum/property_environment/proc/validate_rules()
	return null

/proc/property_environment()
	RETURN_TYPE(/datum/property_environment)
	if(!GLOB.property_environment)
		GLOB.property_environment = new /datum/property_environment
	return GLOB.property_environment
