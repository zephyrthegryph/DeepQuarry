/datum/reagent/eden
	// Eden/snake inherits this identical list and is therefore skipped by the tag table.
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)
	name = REAGENT_EDEN
	id = REAGENT_ID_EDEN
	description = "The ultimate anti toxin unrivaled, it corrects impurities within the body but punishes those who attain them with a burning sensation"
	taste_description = "peace"
	scannable = SCANNABLE_BENEFICIAL
	color = "#00FFBE"
	overdose = REAGENTS_OVERDOSE * 1
	// B8: it used to be 0, so a dose stayed in the blood forever.
	metabolism = REM * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_SLIME) | SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/eden/affect_blood(mob/living/carbon/M, alien, removed)
	// Antitoxin action is the treatment_tags profile; purging impurities burns.
	if(M.injury_load(INJURY_CATEGORY_TOXIC))
		M.injure(INJURY_BURN, 1.2, source = src)
