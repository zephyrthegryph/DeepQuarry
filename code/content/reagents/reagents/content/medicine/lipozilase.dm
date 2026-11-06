// Prussian blue's miniscule antitoxin action is its treatment_tags profile.

/datum/reagent/lipozilase // The anti-nutriment that rapidly removes weight.
	name = REAGENT_LIPOZILASE
	id = REAGENT_ID_LIPOZILASE
	description = "A chemical compound that causes a dangerously powerful fat-burning reaction."
	taste_description = "blandness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	color = "#47AD6D"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DIET

/datum/reagent/lipozilase/affect_blood(mob/living/carbon/M, alien, removed)
	M.adjust_nutrition(-20 * removed)
	if(STATE_GET(M, bodyweight, weight) > 50)
		STATE_SET(M, bodyweight, weight, max(50, STATE_GET(M, bodyweight, weight) - 1.5 * removed)) // B23: 0.3 a tick at REM, scaled by what was metabolised
