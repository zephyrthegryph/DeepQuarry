/datum/reagent/ethanol/hearty_punch
	name = REAGENT_HEARTYPUNCH
	id = REAGENT_ID_HEARTYPUNCH
	description = "Brave bull/syndicate bomb/absinthe mixture resulting in an energizing beverage. Mild alcohol content."
	taste_description = "bravado in the face of disaster"
	color = "#8C0000" // rgb(140, 0, 0)
	strength = 90
	glass_name = REAGENT_HEARTYPUNCH
	glass_desc = "Aromatic beverage served piping hot. According to folk tales it can almost wake the dead."

/datum/reagent/ethanol/hearty_punch/affect_ingest(mob/living/carbon/M, alien, removed)
	// Only works on the critically injured, a gate a continuous tag can't express: mends directly.
	if(M.is_critical())
		M.mend(TREAT_TISSUE_REPAIR, 3 * removed)
		M.mend(TREAT_BURN_CARE, 3 * removed)
		M.mend(TREAT_GENETIC_REPAIR, 5 * removed)
		M.mend(TREAT_OXYGENATION, 4 * removed)
		M.mend(TREAT_ANTITOXIN, 3 * removed)
