// Temperature thresholds, in kelvin. An object's melting and ignition points
// are the lowest of its materials'. Containers aggregate the lowest threshold
// they hold (the reactor watches one ThresholdSet per container, rules.md §4).

/datum/property_def/melting_point
	id = PROP_MELTING_POINT
	name = "Melting point"
	desc = "The lowest melting point of the object's materials."
	unit = PROP_UNIT_KELVIN
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/material/melting_point
	property = PROP_MELTING_POINT
	applies_to = /obj
	unit = PROP_UNIT_KELVIN

/datum/property_provider/material/melting_point/fold(datum/material/M, amount, acc)
	if(isnull(M.melting_point))
		return acc
	return isnull(acc) ? M.melting_point : min(acc, M.melting_point)

/datum/property_def/ignition_point
	id = PROP_IGNITION_POINT
	name = "Ignition point"
	desc = "The lowest ignition point of the object's materials."
	unit = PROP_UNIT_KELVIN
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/material/ignition_point
	property = PROP_IGNITION_POINT
	applies_to = /obj
	unit = PROP_UNIT_KELVIN

/datum/property_provider/material/ignition_point/fold(datum/material/M, amount, acc)
	if(isnull(M.ignition_point))
		return acc
	return isnull(acc) ? M.ignition_point : min(acc, M.ignition_point)

/// A FLAMMABLE object with no flammable material catches where fire can exist.
/datum/property_provider/material/ignition_point/type_value(path, list/variant_vars)
	. = ..()
	if(isnull(.))
		var/obj/O = path
		if(initial(O.resistance_flags) & FLAMMABLE)
			return FIRE_MINIMUM_TEMPERATURE_TO_EXIST

/datum/property_provider/material/ignition_point/instance_value(datum/D)
	. = ..()
	if(isnull(.))
		var/obj/O = D
		if(O.resistance_flags & FLAMMABLE)
			return FIRE_MINIMUM_TEMPERATURE_TO_EXIST

// ---- Per-type heat limits with no material to read them from (H3) ----
// Each replaces a fire_act() override that turned temperature into damage;
// the overheating rule (code/datums/rules/declarations.dm) reads them.

/// A window starts taking heat damage above its maximal_heat.
/datum/property_provider/type_var/window_melting_point
	property = PROP_MELTING_POINT
	applies_to = /obj/structure/window
	unit = PROP_UNIT_KELVIN
	overrides = list(/datum/property_provider/material/melting_point)

/datum/property_provider/type_var/window_melting_point/read_initial(path)
	var/obj/structure/window/W = path
	return initial(W.maximal_heat)

/// An exosuit's hull limit is its max_temperature.
/datum/property_provider/type_var/mecha_melting_point
	property = PROP_MELTING_POINT
	applies_to = /obj/mecha
	unit = PROP_UNIT_KELVIN
	overrides = list(/datum/property_provider/material/melting_point)

/datum/property_provider/type_var/mecha_melting_point/read_initial(path)
	var/obj/mecha/M = path
	return initial(M.max_temperature)

/datum/property_provider/constant/weeds_melting_point
	property = PROP_MELTING_POINT
	applies_to = /obj/effect/alien/weeds
	unit = PROP_UNIT_KELVIN
	value = T0C + 300
	overrides = list(/datum/property_provider/material/melting_point)

/datum/property_provider/constant/web_melting_point
	property = PROP_MELTING_POINT
	applies_to = /obj/effect/spider
	unit = PROP_UNIT_KELVIN
	value = T0C + 300
	overrides = list(/datum/property_provider/material/melting_point)

/// Energy shields take heat damage from any fire.
/datum/property_provider/constant/shield_melting_point
	property = PROP_MELTING_POINT
	applies_to = /obj/effect/shield
	unit = PROP_UNIT_KELVIN
	value = FIRE_MINIMUM_TEMPERATURE_TO_EXIST
	overrides = list(/datum/property_provider/material/melting_point)

/// Rock: the top of the 600-1600 C range.
/datum/property_provider/constant/gargoyle_melting_point
	property = PROP_MELTING_POINT
	applies_to = /obj/structure/gargoyle
	unit = PROP_UNIT_KELVIN
	value = T0C + 1600
	overrides = list(/datum/property_provider/material/melting_point)

/datum/property_def/max_heat_protection
	id = PROP_MAX_HEAT_PROTECTION
	name = "Heat protection"
	desc = "Temperature up to which worn equipment protects from heat."
	unit = PROP_UNIT_KELVIN
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/type_var/max_heat_protection
	property = PROP_MAX_HEAT_PROTECTION
	applies_to = /obj/item
	unit = PROP_UNIT_KELVIN
	state_var = "max_heat_protection_temperature"
	variant_var = "max_heat_protection_temperature"

/datum/property_provider/type_var/max_heat_protection/read_initial(path)
	var/obj/item/I = path
	return initial(I.max_heat_protection_temperature)

/datum/property_def/tag/flammable
	id = TAG_FLAMMABLE
	name = "Flammable"
	desc = "Made of at least one material with an ignition point."

/datum/property_provider/material/flammable
	property = TAG_FLAMMABLE

/datum/property_provider/material/flammable/fold(datum/material/M, amount, acc)
	return (acc || !isnull(M.ignition_point)) ? TRUE : FALSE

/datum/property_def/insulation
	id = PROP_INSULATION
	name = "Insulation"
	desc = "Fraction of heat the object's shell, or a worn layer, keeps from what it covers."
	unit = PROP_UNIT_RATIO
	min_value = 0
	max_value = 1

/datum/property_provider/type_var/insulation
	property = PROP_INSULATION
	applies_to = /obj
	unit = PROP_UNIT_RATIO

/datum/property_provider/type_var/insulation/read_initial(path)
	var/obj/O = path
	return initial(O.insulation)

/obj
	/// PROP_INSULATION: fraction of heat this keeps from what it holds or
	/// covers, 0..1. Containment paths (containment/paths.dm) read it.
	var/insulation = 0
