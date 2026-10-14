// Concrete material, granted-capability and equipment providers.
// ---- Materials ----

/datum/property_provider/material
	source = PROP_SOURCE_MATERIAL
	applies_to = /obj/item

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

// ---- Behaviours ----

/datum/property_provider/behaviour/contribute(datum/D)
	if(!granted(D, behaviour_type))
		return null
	var/datum/capability/def = grant_definition(behaviour_type)
	return def?.property_value(D, property)

/// A granted capability's contribution to property `id` on `E`, or null.
/datum/capability/proc/property_value(datum/E, id)
	return null

// ---- Equipment ----

/// A mob's equipped items, combined with the property's aggregator.
/datum/property_provider/equipment
	source = PROP_SOURCE_EQUIPMENT
	applies_to = /mob

/datum/property_provider/equipment/contribute(datum/D)
	var/mob/M = D
	return dq_property_aggregate(property, M.get_equipped_items())

/datum/property_environment/variant_values(path, variant)
	return dq_variant_vars(path, variant)

/datum/property_environment/validate_rules()
	return dq_rules_validate()
