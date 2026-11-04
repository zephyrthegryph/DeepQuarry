/datum/reagent/performancepeaker
	factors = alist(STAT_ANALGESIA = 10, STAT_SLOWDOWN = -0.5, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_PERFORMANCEPEAKER
	id = REAGENT_ID_PERFORMANCEPEAKER
	description = "A chemical created to bring a body to peak condition. Highly toxic"
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#006666"
	scannable = 1
	dermal_absorption = 0 //This chem is a stronger poison than a benefical chem, with a strength of 15.
	overdose = REAGENTS_OVERDOSE * 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/performancepeaker/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_PARALYZED, -1)
	M.status_adjust(STAT_STUNNED, -1)
	M.status_adjust(STAT_WEAKENED, -1)
	M.injure(INJURY_TOXIN, 15 * removed, source = src)
