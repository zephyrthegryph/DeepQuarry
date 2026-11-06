/////SERAZINE REAGENTS///////

/datum/reagent/serazine
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)
	name = REAGENT_SERAZINE
	id = REAGENT_ID_SERAZINE
	description = "A sweet tasting flower extract, it has very mild anti toxic properties, help with hallucinations and drowsyness, and can be used to make potent drugs."
	taste_description = "sweet nectar"
	reagent_state = LIQUID
	color = "#df9898"
	scannable = 1
	dermal_absorption = 0.25
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/serazine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_DROWSY, -(3 * removed))
	M.status_adjust(STAT_HALLUCINATING, -(6 * removed))
