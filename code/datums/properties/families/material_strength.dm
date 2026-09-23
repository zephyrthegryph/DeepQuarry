// Material strength (doc/rewrite/damage.md §4 step 4, roadmap D2). An object's
// hardness, yield strength and fracture toughness are the weakest of its
// materials', like its melting point. Impact response (impact_response.dm)
// reads them to resist blunt, sharp and piercing hits.

/datum/property_def/hardness
	id = PROP_HARDNESS
	name = "Hardness"
	desc = "The lowest hardness of the object's materials."
	unit = PROP_UNIT_RATIO
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/material/hardness
	property = PROP_HARDNESS
	unit = PROP_UNIT_RATIO

/datum/property_provider/material/hardness/fold(datum/material/M, amount, acc)
	return isnull(acc) ? M.hardness : min(acc, M.hardness)

/datum/property_def/yield_strength
	id = PROP_YIELD_STRENGTH
	name = "Yield strength"
	desc = "The lowest yield strength of the object's materials."
	unit = PROP_UNIT_RATIO
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/material/yield_strength
	property = PROP_YIELD_STRENGTH
	unit = PROP_UNIT_RATIO

/datum/property_provider/material/yield_strength/fold(datum/material/M, amount, acc)
	return isnull(acc) ? M.yield_strength : min(acc, M.yield_strength)

/datum/property_def/fracture_toughness
	id = PROP_FRACTURE_TOUGHNESS
	name = "Fracture toughness"
	desc = "The lowest fracture toughness of the object's materials."
	unit = PROP_UNIT_RATIO
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/material/fracture_toughness
	property = PROP_FRACTURE_TOUGHNESS
	unit = PROP_UNIT_RATIO

/datum/property_provider/material/fracture_toughness/fold(datum/material/M, amount, acc)
	return isnull(acc) ? M.fracture_toughness : min(acc, M.fracture_toughness)
