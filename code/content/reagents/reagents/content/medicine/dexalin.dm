/datum/reagent/dexalin
	treatment_tags = list(TREAT_OXYGENATION = 0.5)
	// Loads the blood with oxygen: more carried per unit of saturation.
	factors = alist(STAT_O2_CARRIAGE = 1.25)
	species_factors = alist(IS_SLIME = alist(STAT_ANALGESIA = 15))
	name = REAGENT_DEXALIN
	id = REAGENT_ID_DEXALIN
	description = REAGENT_DEXALIN + " is used in the treatment of oxygen deprivation."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#0080FF"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	metabolism = REM * 0.25
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	species_injuries_blood = alist(IS_VOX = alist(INJURY_TOXIN = 24))

/datum/reagent/dexalin/affect_blood(mob/living/carbon/M, alien, removed)
	// Oxygenation is the treatment_tags profile. Kept: a random dose-gated burst.
	if(alien == IS_SLIME && dose >= 15)
		if(prob(15))
			to_chat(M, span_notice("You have a moment of clarity as you collapse."))
			// Random burst, not a continuous effect: mend directly.
			M.mend(TREAT_NEURAL_REPAIR, 20 * removed)
			M.status_at_least(STAT_WEAKENED, 6)

	holder.remove_reagent(REAGENT_ID_LEXORIN, 8 * removed)
