/datum/reagent/lipostipo // The drug that rapidly increases weight.
	name = REAGENT_LIPOSTIPO
	id = REAGENT_ID_LIPOSTIPO
	description = "A chemical compound that causes a dangerously powerful fat-adding reaction."
	taste_description = "blubber"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#61731C"
	scannable = SCANNABLE_BENEFICIAL
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DIET

/datum/reagent/lipostipo/affect_blood(mob/living/carbon/M, alien, removed)
	// B23: the weight-gain drug feeds (it was a copy of lipozilase and starved you).
	M.adjust_nutrition(20 * removed)
	if(sparse_get_or(M, weight, DEFAULT_MOB_WEIGHT) < 500)
		sparse_set_or(M, weight, min(500, sparse_get_or(M, weight, DEFAULT_MOB_WEIGHT) + 1.5 * removed), DEFAULT_MOB_WEIGHT)
