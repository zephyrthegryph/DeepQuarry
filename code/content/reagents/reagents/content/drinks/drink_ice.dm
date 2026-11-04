/datum/reagent/drink/ice
	name = REAGENT_ICE
	id = REAGENT_ID_ICE
	description = "Frozen water, your dentist wouldn't like you chewing this."
	taste_description = "ice"
	reagent_state = SOLID
	color = "#619494"
	adj_temp = -5

	glass_name = REAGENT_ID_ICE
	glass_desc = "Generally, you're supposed to put something else in there too..."
	glass_icon = DRINK_ICON_NOISY

/datum/reagent/drink/ice
	species_chill = 1 // nonzero enables the chill; the rate itself is random (species_chill_rate())

/datum/reagent/drink/ice/species_chill_rate()
	return rand(1, 3)

/datum/reagent/drink/ice/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/ice/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)
