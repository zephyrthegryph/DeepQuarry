/datum/reagent/chlorine
	name = REAGENT_CHLORINE
	id = REAGENT_ID_CHLORINE
	description = "A chemical element with a characteristic odour."
	taste_description = "pool water"
	reagent_state = GAS
	color = "#808080"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 0.15

/datum/reagent/chlorine/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_CORROSIVE, 1*REM, source = src)

/datum/reagent/chlorine/affect_touch(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_CORROSIVE, 1*REM, source = src)
