/datum/reagent/nutriment/honey
	name = REAGENT_HONEY
	id = REAGENT_ID_HONEY
	description = "A golden yellow syrup, loaded with sugary sweetness."
	taste_description = "sweetness"
	nutriment_factor = 10
	color = "#FFFF00"
	cup_prefix = REAGENT_ID_HONEY

/datum/reagent/nutriment/honey/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	var/effective_dose = dose
	if(issmall(M))
		effective_dose *= 2

	sugar_sedation(M, effective_dose)
