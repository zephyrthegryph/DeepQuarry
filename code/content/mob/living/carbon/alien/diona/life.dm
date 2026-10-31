//Dionaea regenerate health and nutrition in light.
/mob/living/carbon/alien/diona/life_environment_due()
	return TRUE

/mob/living/carbon/alien/diona/life_environment_exchange(datum/gas_mixture/environment)

	var/light_amount = 0 //how much light there is in the place, affects receiving nutrition and healing
	if(isturf(src.loc)) //else, there's considered to be no light
		var/turf/T = src.loc
		light_amount = T.get_lumcount() * 5

	src.adjust_nutrition(light_amount)

	if(light_amount > 2) //if there's enough light, heal
		src.mend(TREAT_TISSUE_REPAIR, 1)
		src.mend(TREAT_BURN_CARE, 1)
		src.mend(TREAT_ANTITOXIN, 1)
		src.mend(TREAT_OXYGENATION, 1)


	if(!src.client)
		src.npc_behaviour(src)
