/datum/reagent/toxin/plantbgone
	name = REAGENT_PLANTBGONE
	id = REAGENT_ID_PLANTBGONE
	description = "A harmful toxic mixture to kill plantlife. Do not ingest!"
	dermal_absorption = 0.1 //Very weak.
	taste_mult = 1
	reagent_state = LIQUID
	color = "#49002E"
	strength = 4
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/plantbgone/touch_turf(turf/T)
	..()
	if(istype(T, /turf/simulated/wall))
		var/turf/simulated/wall/W = T
		if(locate_on(W, /obj/effect/overlay/wallrot))
			for(var/obj/effect/overlay/wallrot/E in turf_contents_of_type(W, /obj/effect/overlay/wallrot))
				dissolved(E)
			W.visible_message(span_notice("The fungi are completely dissolved by the solution!"))

/datum/reagent/toxin/plantbgone/touch_obj(obj/O, volume)
	..()
	if(istype(O, /obj/effect/plant))
		dissolved(O)
	else if(istype(O, /obj/effect/alien/weeds/))
		var/obj/effect/alien/weeds/alien_weeds = O
		alien_weeds.take_damage(rand(15, 35), BRUTE)

/datum/reagent/toxin/plantbgone
	// Herbicide: harmless to everyone but plant people.
	species_injuries_blood = alist(IS_DIONA = alist(INJURY_TOXIN = 50))
	species_injuries_touch = alist(IS_DIONA = alist(INJURY_TOXIN = 50))

/datum/reagent/toxin/plantbgone/affect_blood(mob/living/carbon/M, alien, removed)
	return

/datum/reagent/toxin/plantbgone/affect_touch(mob/living/carbon/M, alien, removed)
	return
