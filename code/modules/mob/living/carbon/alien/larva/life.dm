
//Larvae regenerate health and nutrition from plasma and alien weeds.
/mob/living/carbon/alien/larva/handle_environment(datum/gas_mixture/environment)

	if(!environment) return

	var/turf/T = get_turf(src)
	if(LINDA_GAS_AMT(environment, GAS_PHORON) > 0 || (T && locate(/obj/effect/alien/weeds) in T.contents))
		update_progression()
		adjustBruteLoss(-1)
		adjustFireLoss(-1)
		adjustToxLoss(-1)
		adjustOxyLoss(-1)
