/datum/reagent/drink/nuclearwaste
	name = REAGENT_NUCLEARWASTE
	id = REAGENT_ID_NUCLEARWASTE
	description = "A viscous, glowing slurry."
	taste_description = "sour honey drops"
	nutriment_factor = 15
	color = "#7FFF00" // rgb(127,255,0)
	water_based = FALSE

	glass_name = REAGENT_NUCLEARWASTE
	glass_desc = "Sadly, no super powers."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list(DRINK_FIZZ)
	allergen_type = ALLERGEN_VEGETABLE //Made from oilslick, so has the same allergens.

/datum/reagent/drink/nuclearwaste/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	M.bloodstr.add_reagent(REAGENT_ID_RADIUM, 0.3)

/datum/reagent/drink/nuclearwaste/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	M.ingested.add_reagent(REAGENT_ID_RADIUM, 0.25)
