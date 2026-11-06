/datum/reagent/radium
	name = REAGENT_RADIUM
	id = REAGENT_ID_RADIUM
	description = "Radium is an alkaline earth metal. It is extremely radioactive."
	taste_mult = 0	//Apparently radium is tasteless
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#C7C7C7"
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/radium/touch_turf(turf/T)
	..()
	if(volume >= 3)
		if(!istype(T, /turf/space))
			var/obj/effect/decal/cleanable/greenglow/glow = locate(/obj/effect/decal/cleanable/greenglow, T)
			if(!glow)
				new /obj/effect/decal/cleanable/greenglow(T)
			return

/datum/reagent/radium/concentrated
	name = REAGENT_CONCENTRATEDRADIUM
	id = REAGENT_ID_CONCENTRATEDRADIUM
	description = "Concentrated Radium is a more potent variant of regular radium, able to pierce and irradiate a subject through their skin."
	taste_mult = 0	//Apparently radium is tasteless
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#C7C7C7"
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/radium/affect_blood(mob/living/carbon/M, alien, removed)
	if(issmall(M)) removed *= 2
	M.apply_effect(10 * removed, IRRADIATE, 0) // Radium may increase your chances to cure a disease

/datum/reagent/radium/affect_touch(mob/living/carbon/M, alien, removed)
	if(issmall(M)) removed *= 2
	M.apply_effect(10 * removed, IRRADIATE, 0) // Radium may increase your chances to cure a disease
