/datum/reagent/drugs/citalopram
	name = REAGENT_CITALOPRAM
	id = REAGENT_ID_CITALOPRAM
	description = "Stabilizes the mind a little."
	taste_description = "mild peppermint"
	color = "#FF80FF"
	scannable = SCANNABLE_BENEFICIAL
	high_message_list = list("Everything feels a bit more steady.", "Your mind feels stable.")
	sober_message_list = list("You feel a little tired.", "You feel a little more listless...")
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/drugs/citalopram/affect_blood(mob/living/carbon/M, alien, removed)
	..()

	M.status_set(STAT_FEAR, max((M.status_units(STAT_FEAR) - 3),0))
