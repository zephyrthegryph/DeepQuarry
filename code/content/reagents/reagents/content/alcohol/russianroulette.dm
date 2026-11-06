/datum/reagent/ethanol/russianroulette
	name = REAGENT_RUSSIANROULETTE
	id = REAGENT_ID_RUSSIANROULETTE
	description = "The perfect drink for wagering your liver on a game of cards."
	taste_description = "coffee, vodka, cream, and a hot metal slug"
	strength = 30
	color = "#d3785d"

	glass_name = REAGENT_RUSSIANROULETTE
	glass_desc = "A favorite drink amongst the Pan-Slavic speaking community."

/datum/reagent/ethanol/russianroulette/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		M.status_at_least(STAT_STUNNED, 2)
