/datum/reagent/dryagent
	name = REAGENT_DRYAGENT
	id = REAGENT_ID_DRYAGENT
	description = "A desiccant. Can be used to dry things."
	taste_description = "dryness"
	reagent_state = LIQUID
	color = "#A70FFF"
	scannable = 1
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY

/datum/reagent/dryagent
	// Why are you giving this to Prometheans or Dionas. You're going to DRY them. (2 burn x 1.25)
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BURN = 2.5))

/datum/reagent/dryagent/touch_obj(obj/O, amount)
	if(istype(O, /obj/item/clothing/shoes/galoshes) && O.loc)
		replace_with(O, /obj/item/clothing/shoes/dry_galoshes)
		remove_self(10)

/datum/reagent/dryagent/touch_turf(turf/T)
	..()
	if(volume >= 5)
		if(istype(T, /turf/simulated/floor))
			var/turf/simulated/floor/F = T
			if(F.wet)
				F.set_wet(0)
	return
