/datum/reagent/ethanol/deathbell
	name = REAGENT_DEATHBELL
	id = REAGENT_ID_DEATHBELL
	description = "A successful experiment to make the most alcoholic thing possible."
	taste_description = "your brains smashed out by a smooth brick of hard, ice cold alcohol"
	color = "#9f6aff"
	taste_mult = 5
	strength = 10
	adj_temp = 10
	targ_temp = 330

	glass_name = REAGENT_DEATHBELL
	glass_desc = "The perfect blend of the most alcoholic things a bartender can get their hands on."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_DAIRY|ALLERGEN_FRUIT //Made from antifreeze(vodka(grains),cream(dairy)), gargleblaster(vodka(grains),gin(fruit),whiskey(grains),cognac(fruit),lime juice(fruit)), and syndicate bomb(beer(grain),whiskeycola(whiskey(grain)))

/datum/reagent/ethanol/deathbell/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		if(dose * strength >= strength) // Early warning
			M.status_adjust(STAT_DIZZY, 24) // Intentionally higher than normal to compensate for it's previous effects.
		if(dose * strength >= strength * 2.5) // Slurring takes longer. Again, intentional.
			M.status_at_least(STAT_SLURRING, 30)
