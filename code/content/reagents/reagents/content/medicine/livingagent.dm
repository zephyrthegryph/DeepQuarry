//meteroidliquid
/datum/reagent/livingagent
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.5,
		TREAT_BURN_CARE = 0.5,
		TREAT_OXYGENATION = 0.4,
		TREAT_ANTITOXIN = 0.4,
	)
	factors = alist(STAT_ANALGESIA = -20)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_LIVINGAGENT
	id = REAGENT_ID_LIVINGAGENT
	description = "Fill the body with life, while making it more senstive to stimulus."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8040FF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 3
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/livingagent/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_DRUGGED, 5)
	M.status_at_least(STAT_CONFUSED, 5)
