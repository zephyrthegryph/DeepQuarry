// Property providers (doc/rewrite/rules.md §1).
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
//   /datum/property_provider/component  a component on the instance.
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

// ---- Materials ----

/datum/property_provider/material
	source = PROP_SOURCE_MATERIAL
	applies_to = /obj/item
	state_var = "material_overrides"

/datum/property_provider/material/type_value(path, list/variant_vars)
	return from_matter(dq_property_type_matter(path))

/datum/property_provider/material/instance_value(datum/D)
	// Composition is derived from the blueprint plus this instance's saved overrides.
	var/obj/O = D
	return from_matter(O.material_totals())

/// Fold a matter list (material name -> amount) into a value: calls fold()
/// once per known material.
/datum/property_provider/material/proc/from_matter(list/matter)
	if(!length(matter))
		return null
	. = null
	for(var/name in matter)
		var/datum/material/M = GLOB.name_to_material[name]
		if(!M)
			continue
		. = fold(M, matter[name], .)

/datum/property_provider/material/proc/fold(datum/material/M, amount, acc)
	return acc

/// A type's material totals from its declared blueprint and total, read without an
/// instance. The one place per-type composition is read.
/proc/dq_property_type_matter(path)
	return dq_type_material_totals(path)

// ---- Components ----

/datum/property_provider/component
	source = PROP_SOURCE_COMPONENT
	applies_to = /datum
	/// Component type whose presence contributes.
	var/component_type

/datum/property_provider/component/contribute(datum/D)
	var/datum/component/C = D.GetComponent(component_type)
	return C?.property_value(property)

/// A component's contribution to property `id`, or null.
/datum/component/proc/property_value(id)
	return null

// ---- Equipment ----

/// A mob's equipped items, combined with the property's aggregator.
/datum/property_provider/equipment
	source = PROP_SOURCE_EQUIPMENT
	applies_to = /mob

/datum/property_provider/equipment/contribute(datum/D)
	var/mob/M = D
	return dq_property_aggregate(property, M.get_equipped_items())
