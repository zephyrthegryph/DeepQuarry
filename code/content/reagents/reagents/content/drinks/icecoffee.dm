/datum/reagent/drink/coffee/icecoffee
	name = REAGENT_ICECOFFEE
	id = REAGENT_ID_ICECOFFEE
	description = "Coffee and ice, refreshing and cool."
	color = "#102838"
	adj_temp = -5

	glass_name = "iced coffee"
	glass_desc = "A drink to perk you up and refresh you!"
	glass_special = list(DRINK_ICE)

/datum/reagent/drink/coffee/icecoffee
	species_chill = 0.5

/datum/reagent/drink/coffee/icecoffee/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/coffee/icecoffee/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)
