/datum/reagent/ethanol/beer
	name = REAGENT_BEER
	id = REAGENT_ID_BEER
	description = "An alcoholic beverage made from malted grains, hops, yeast, and water."
	taste_description = "beer"
	color = "#FFD300"
	strength = 50
	nutriment_factor = 1

	glass_name = REAGENT_ID_BEER
	glass_desc = "A freezing pint of beer"

	allergen_type = ALLERGEN_GRAINS //Made from grains

/datum/reagent/ethanol/beer/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		if(inert_for(M))
			return
		M.adjust_nutrition((M.food_preference(allergen_type) / 2) * removed) //RS edit
		M.status_adjust(STAT_JITTERY, -3)

/datum/reagent/ethanol/beer/lite
	name = REAGENT_LITEBEER
	id = REAGENT_ID_LITEBEER
	description = "An alcoholic beverage made from malted grains, hops, yeast, water, and water."
	taste_description = "bad beer"
	color = "#FFD300"
	strength = 75
	nutriment_factor = 1

	glass_name = "lite beer"
	glass_desc = "A freezing pint of lite beer"

	allergen_type = ALLERGEN_GRAINS //Made from grains
