/datum/reagent/lexorin
	name = REAGENT_LEXORIN
	id = REAGENT_ID_LEXORIN
	scannable = SCANNABLE_DIFFICULT
	description = "Lexorin temporarily stops respiration. Causes tissue damage."
	taste_description = "acid"
	reagent_state = LIQUID
	dermal_absorption = 0.2 //Causes tissue damage, so can be presumed to penetrate through the skin somewhat.
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/lexorin
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/lexorin/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		M.apply_effect(5, AGONY, 0)
		M.injure(INJURY_TOXIN, 3 * removed, source = src)
		if(prob(10))
			to_chat(M, span_warning("Your cellular mass hardens for a moment."))
			M.status_at_least(STAT_STUNNED, 6)
		return
	M.injure(INJURY_CORROSIVE, 3 * removed, source = src)
	if(M.losebreath() < 15)
		M.AdjustLosebreath(1)
