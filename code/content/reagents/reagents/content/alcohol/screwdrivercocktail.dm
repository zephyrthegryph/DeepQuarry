/datum/reagent/ethanol/screwdrivercocktail
	name = REAGENT_SCREWDRIVERCOCKTAIL
	id = REAGENT_ID_SCREWDRIVERCOCKTAIL
	description = "Vodka, mixed with plain ol' orange juice. The result is surprisingly delicious."
	taste_description = "oranges"
	color = "#A68310"
	strength = 15

	glass_name = REAGENT_SCREWDRIVERCOCKTAIL
	glass_desc = "A simple, yet superb mixture of Vodka and orange juice. Just the thing for the tired engineer."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from vodka(grains) and orange juice(fruit)

/datum/reagent/ethanol/screwdrivercocktail/on_mob_life(mob/living/carbon/drinker, seconds_per_tick, metabolization_ratio)
	. = ..()
	add_trait(drinker, TRAIT_HALT_RADIATION_EFFECTS, "[type]")
	if (has_trait(drinker, TRAIT_IRRADIATED))
		// Only while irradiated, a gate a continuous tag can't express: mends directly.
		drinker.mend(TREAT_ANTITOXIN, 2 * metabolization_ratio * seconds_per_tick)

/datum/reagent/ethanol/screwdrivercocktail/on_mob_end_metabolize(mob/living/drinker)
	. = ..()
	remove_trait(drinker, TRAIT_HALT_RADIATION_EFFECTS, "[type]")
