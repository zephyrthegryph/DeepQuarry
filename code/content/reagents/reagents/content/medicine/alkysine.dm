/datum/reagent/alkysine
	treatment_tags = list(TREAT_NEURAL_REPAIR = 0.5)
	factors = alist(STAT_ANALGESIA = 10)
	species_factors = alist(IS_DIONA = null, IS_SLIME = alist(STAT_ANALGESIA = 2.5))
	name = REAGENT_ALKYSINE
	id = REAGENT_ID_ALKYSINE
	description = REAGENT_ALKYSINE + " is a drug used to lessen the damage to neurological tissue after a catastrophic injury. Can heal brain tissue."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FFFF66"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/alkysine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/alkysine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		if(M.injury_load(INJURY_CATEGORY_NEURAL) >= 10)
			M.status_at_least(STAT_WEAKENED, 5)
		if(dose >= 10 && M.status_units(STAT_PARALYZED) < 40)
			M.status_adjust(STAT_PARALYZED, 1) //Messing with the core with a simple chemical probably isn't the best idea.
	// Brain repair is alkysine's TREAT_NEURAL_REPAIR tag (body/treatment.dm);
	// past the salvage band a swollen brain outpaces it (lesions.dm).
