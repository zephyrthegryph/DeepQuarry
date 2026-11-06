/datum/reagent/dexalinp
	treatment_tags = list(TREAT_OXYGENATION = 1.0)
	factors = alist(STAT_O2_CARRIAGE = 1.5)
	species_factors = alist(IS_SLIME = alist(STAT_ANALGESIA = 25))
	name = REAGENT_DEXALINP
	id = REAGENT_ID_DEXALINP
	description = REAGENT_DEXALINP + " is used in the treatment of oxygen deprivation. It is highly effective."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#0040FF"
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 1.25
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	species_injuries_blood = alist(IS_VOX = alist(INJURY_TOXIN = 9))

/datum/reagent/dexalinp/affect_blood(mob/living/carbon/M, alien, removed)
	// Oxygenation is the treatment_tags profile. Kept: a random dose-gated burst.
	if(alien == IS_SLIME && dose >= 10)
		if(prob(25))
			to_chat(M, span_notice("You have a moment of clarity, as you feel your tubes lose pressure rapidly."))
			// Random burst, not a continuous effect: mend directly.
			M.mend(TREAT_NEURAL_REPAIR, 8 * removed)
			M.status_at_least(STAT_WEAKENED, 3)

	holder.remove_reagent(REAGENT_ID_LEXORIN, 3 * removed)
