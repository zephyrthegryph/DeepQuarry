/datum/reagent/impedrezene
	name = REAGENT_IMPEDREZENE
	id = REAGENT_ID_IMPEDREZENE
	scannable = SCANNABLE_ADVANCED
	description = "Impedrezene is a narcotic that impedes one's ability by slowing down the higher brain cell functions."
	taste_description = "numbness"
	reagent_state = LIQUID
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE
	filtered_organs = list(O_SPLEEN)
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/impedrezene
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/impedrezene/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_JITTERY, -5)
	if(prob(80))
		M.injure(INJURY_NEURAL, 0.1 * removed, source = src)
	if(prob(50))
		M.status_at_least(STAT_DROWSY, 3)
	if(prob(10))
		M.emote("drool")
