/datum/reagent/thermite
	name = REAGENT_THERMITE
	id = REAGENT_ID_THERMITE
	description = "Thermite produces an aluminothermic reaction known as a thermite reaction. Can be used to melt walls."
	taste_description = "sweet tasting metal"
	reagent_state = SOLID
	dermal_absorption = 0
	scannable = SCANNABLE_ADVANCED
	color = "#673910"
	touch_met = 50
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/thermite/touch_turf(turf/T)
	..()
	if(volume >= 5)
		if(istype(T, /turf/simulated/wall))
			var/turf/simulated/wall/W = T
			W.set_thermite(TRUE)
			remove_self(5)
	return

/datum/reagent/thermite/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		L.adjust_fire_stacks(amount / 5)

/datum/reagent/thermite/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_BURN, 3 * removed, source = src)
