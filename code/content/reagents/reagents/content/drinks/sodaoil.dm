/datum/reagent/drink/sodaoil //Mixed with normal drinks to make a 'potable' version for Prometheans if mixed 1-1. Dilution is key.
	name = REAGENT_SODAOIL
	id = REAGENT_ID_SODAOIL
	description = "A thick, bubbling soda."
	taste_description = "chewy water"
	nutriment_factor = 10
	color = "#F0FFF0" // rgb(245,255,250)
	water_based = FALSE

	glass_name = REAGENT_SODAOIL
	glass_desc = "A pitiful sludge that looks vaguely like a soda.. if you look at it a certain way."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_VEGETABLE //Made from corn oil

/datum/reagent/drink/sodaoil/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(M.bloodstr) // If, for some reason, they are injected, dilute them as well.
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/drink))
				var/datum/reagent/drink/D = R
				if(D.water_based)
					// Conditional on other drinks being present: mends directly.
					M.mend(TREAT_ANTITOXIN, removed * 3)

/datum/reagent/drink/sodaoil/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(M.ingested) // Find how many drinks are causing tox, and negate them.
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/drink))
				var/datum/reagent/drink/D = R
				if(D.water_based)
					// Conditional on other drinks being present: mends directly.
					M.mend(TREAT_ANTITOXIN, removed * 2)
