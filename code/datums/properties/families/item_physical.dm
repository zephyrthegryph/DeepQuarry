// Physical item properties: size class and mass.
//
// Size class comes from the `w_class` var (initial, variant, then saved
// state). Mass comes from the item's `matter` list; a mob's mass is the sum of
// what it has equipped, plus any component contribution.

/datum/property_def/size_class
	id = PROP_SIZE_CLASS
	name = "Size class"
	desc = "ITEMSIZE_* class. A container aggregates the largest it holds."
	unit = PROP_UNIT_SIZE_CLASS
	aggregator = PROP_AGG_MAX
	high_word = "big"
	low_word = "small"
	min_value = 0
	max_value = ITEMSIZE_NO_CONTAINER

/datum/property_provider/type_var/size_class
	property = PROP_SIZE_CLASS
	applies_to = /obj
	unit = PROP_UNIT_SIZE_CLASS
	state_var = "w_class"
	variant_var = "w_class"

/datum/property_provider/type_var/size_class/read_initial(path)
	var/obj/O = path
	return initial(O.w_class)

/datum/property_def/mass
	id = PROP_MASS
	name = "Mass"
	desc = "Mass of the material an object is made of. Containers sum their contents."
	unit = PROP_UNIT_KILOGRAMS
	aggregator = PROP_AGG_SUM
	min_value = 0
	high_word = "heavy"
	low_word = "light"

/datum/property_provider/material/mass
	property = PROP_MASS
	unit = PROP_UNIT_KILOGRAMS

/datum/property_provider/material/mass/fold(datum/material/M, amount, acc)
	return (acc || 0) + amount * MATTER_UNIT_KG

/datum/property_provider/equipment/mass
	property = PROP_MASS
	unit = PROP_UNIT_KILOGRAMS

// ---- Tags ----

/datum/property_def/tag/sharp
	id = TAG_SHARP
	name = "Sharp"
	desc = "Cuts."

/datum/property_provider/type_var/tag/sharp
	property = TAG_SHARP
	applies_to = /obj/item
	state_var = "sharp"
	variant_var = "sharp"

/datum/property_provider/type_var/tag/sharp/read_initial(path)
	var/obj/item/I = path
	return initial(I.sharp)

/datum/property_def/tag/conductive
	id = TAG_CONDUCTIVE
	name = "Conductive"
	desc = "Made of at least one conductive material."

/datum/property_provider/material/conductive
	property = TAG_CONDUCTIVE

/datum/property_provider/material/conductive/fold(datum/material/M, amount, acc)
	return (acc || M.conductive) ? TRUE : FALSE

/datum/property_def/heat_capacity
	id = PROP_HEAT_CAPACITY
	name = "Heat capacity"
	desc = "Heat capacity of the material an object is made of. Containers sum their contents."
	unit = PROP_UNIT_HEAT_CAPACITY
	aggregator = PROP_AGG_SUM
	min_value = 0

/datum/property_provider/material/heat_capacity
	property = PROP_HEAT_CAPACITY
	unit = PROP_UNIT_HEAT_CAPACITY

/// Specific heat is J/(kg K), so each material adds kg x specific heat.
/datum/property_provider/material/heat_capacity/fold(datum/material/M, amount, acc)
	return (acc || 0) + amount * MATTER_UNIT_KG * M.specific_heat

/datum/property_def/tag/paperwork
	id = TAG_PAPERWORK
	name = "Paperwork"
	desc = "Paper, photos and bundles: what folders and clipboards hold."

/datum/property_provider/type_var/tag/paperwork
	property = TAG_PAPERWORK
	applies_to = /obj/item

/datum/property_provider/type_var/tag/paperwork/read_initial(path)
	return ispath(path, /obj/item/paper) || ispath(path, /obj/item/photo) || ispath(path, /obj/item/paper_bundle)
