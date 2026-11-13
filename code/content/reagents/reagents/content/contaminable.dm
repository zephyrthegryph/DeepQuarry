// Reagents a dispenser or supply never rolls impurities for (/datum/reagent/proc/source_contaminable(), code/domains/world_model/reagents/contaminants.dm):
// drinks, ethanol, nutriment, water and blood are not chemistry stock.

/datum/reagent/drink/source_contaminable()
	return FALSE

/datum/reagent/ethanol/source_contaminable()
	return FALSE

/datum/reagent/nutriment/source_contaminable()
	return FALSE

/datum/reagent/water/source_contaminable()
	return FALSE

/datum/reagent/blood/source_contaminable()
	return FALSE
