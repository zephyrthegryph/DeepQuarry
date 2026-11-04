/datum/reagent/ethanol/soemmerfire
	name = REAGENT_SOEMMERFIRE
	id = REAGENT_ID_SOEMMERFIRE
	description = "A painfully hot mixed drink, for when you absolutely need to hurt right now."
	taste_description = "pure fire"
	color = "#d13b21" // rgb(209, 59, 33)
	strength = 25

	glass_name = REAGENT_SOEMMERFIRE
	glass_desc = "A painfully hot mixed drink, for when you absolutely need to hurt right now."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from manhattan(whiskey(grains), vermouth(fruit))

/datum/reagent/ethanol/soemmerfire/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	handle_spicy(M, alien, removed)
