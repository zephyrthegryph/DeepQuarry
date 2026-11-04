/datum/reagent/nutriment/flour
	name = REAGENT_FLOUR
	id = REAGENT_ID_FLOUR
	description = "This is what you rub all over yourself to pretend to be a ghost."
	taste_description = "chalky wheat"
	reagent_state = SOLID
	nutriment_factor = 1
	color = "#FFFFFF"
	allergen_type = ALLERGEN_GRAINS //Flour is made from grain

/datum/reagent/nutriment/flour/touch_turf(turf/simulated/T)
	..()
	if(!istype(T, /turf/space))
		new /obj/effect/decal/cleanable/flour(T)
