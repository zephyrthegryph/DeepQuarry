// Material strength (doc/rewrite/damage.md §4 step 4, roadmap D2). An object's
// strength and toughness (two of the material card's stats) are the weakest of
// its materials, like its melting point. Impact response (impact_response.dm)
// reads them to resist blunt, sharp and piercing hits.

/datum/property_def/strength
	id = PROP_STRENGTH
	name = "Strength"
	desc = "The lowest strength of the object's materials."
	unit = PROP_UNIT_RATIO
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/material/strength
	property = PROP_STRENGTH
	unit = PROP_UNIT_RATIO

/datum/property_provider/material/strength/fold(datum/material/M, amount, acc)
	return isnull(acc) ? M.strength : min(acc, M.strength)

/datum/property_def/toughness
	id = PROP_TOUGHNESS
	name = "Toughness"
	desc = "The lowest toughness of the object's materials."
	unit = PROP_UNIT_RATIO
	aggregator = PROP_AGG_MIN
	min_value = 0

/datum/property_provider/material/toughness
	property = PROP_TOUGHNESS
	unit = PROP_UNIT_RATIO

/datum/property_provider/material/toughness/fold(datum/material/M, amount, acc)
	return isnull(acc) ? M.toughness : min(acc, M.toughness)
