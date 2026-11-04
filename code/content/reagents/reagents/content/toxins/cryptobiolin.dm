/datum/reagent/cryptobiolin
	name = REAGENT_CRYPTOBIOLIN
	id = REAGENT_ID_CRYPTOBIOLIN
	scannable = SCANNABLE_ADVANCED
	description = "Cryptobiolin causes confusion and dizzyness."
	taste_description = "sourness"
	reagent_state = LIQUID
	color = "#000055"
	metabolism = REM * 0.5
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/cryptobiolin
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	species_strength = alist(IS_SLIME = 0.15) // ~1/6

/datum/reagent/cryptobiolin/affect_blood(mob/living/carbon/M, alien, removed)
	var/drug_strength = 4
	if(M.species.chem_strength_tox > 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
		drug_strength *= M.species.chem_strength_tox
	drug_strength *= species_mult(M)

	M.status_adjust(STAT_DIZZY, drug_strength)
	M.status_at_least(STAT_CONFUSED, drug_strength * 5)
