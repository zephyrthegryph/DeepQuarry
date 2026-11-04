/datum/reagent/drink/hell_ramen
	name = REAGENT_HELLRAMEN
	id = REAGENT_ID_HELLRAMEN
	description = "The noodles are boiled, the flavors are artificial, just like being back in school."
	taste_description = "noodles and spice"
	taste_mult = 1.7
	reagent_state = LIQUID
	color = "#302000"
	nutrition = 5

/datum/reagent/drink/hell_ramen/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	handle_spicy(M, alien, removed)
