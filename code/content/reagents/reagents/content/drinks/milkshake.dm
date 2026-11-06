/datum/reagent/drink/milkshake
	name = REAGENT_MILKSHAKE
	id = REAGENT_ID_MILKSHAKE
	description = "Glorious brainfreezing mixture."
	taste_description = "vanilla milkshake"
	color = "#AEE5E4"
	adj_temp = -9

	glass_name = REAGENT_ID_MILKSHAKE
	glass_desc = "Glorious brainfreezing mixture."
	allergen_type = ALLERGEN_DAIRY //Made with dairy products

/datum/reagent/drink/milkshake/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	var/effective_dose = dose/2
	if(issmall(M))
		effective_dose *= 2

	sugar_sedation(M, effective_dose)

/datum/reagent/drink/milkshake/chocoshake
	name = REAGENT_CHOCOSHAKE
	id = REAGENT_ID_CHOCOSHAKE
	description = "A refreshing chocolate milkshake."
	taste_description = "cold refreshing chocolate and cream"
	color = "#8e6f44" // rgb(142, 111, 68)
	adj_temp = -9

	glass_name = REAGENT_CHOCOSHAKE
	glass_desc = "A refreshing chocolate milkshake, just like mom used to make."
	allergen_type = ALLERGEN_DAIRY|ALLERGEN_CHOCOLATE //Made with dairy products

/datum/reagent/drink/milkshake/berryshake
	name = REAGENT_BERRYSHAKE
	id = REAGENT_ID_BERRYSHAKE
	description = "A refreshing berry milkshake."
	taste_description = "cold refreshing berries and cream"
	color = "#ffb2b2" // rgb(255, 178, 178)
	adj_temp = -9

	glass_name = REAGENT_BERRYSHAKE
	glass_desc = "A refreshing berry milkshake, just like mom used to make."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_DAIRY //Made with berry juice and dairy products

/datum/reagent/drink/milkshake/coffeeshake
	name = REAGENT_COFFEESHAKE
	id = REAGENT_ID_COFFEESHAKE
	description = "A refreshing coffee milkshake."
	taste_description = "cold energizing coffee and cream"
	color = "#8e6f44" // rgb(142, 111, 68)
	adj_temp = -9
	adj_dizzy = -5
	adj_drowsy = -3
	adj_sleepy = -2

	glass_name = REAGENT_COFFEESHAKE
	glass_desc = "An energizing coffee milkshake, perfect for hot days at work.."
	allergen_type = ALLERGEN_DAIRY|ALLERGEN_COFFEE //Made with coffee and dairy products

/datum/reagent/drink/milkshake/coffeeshake/overdose(mob/living/carbon/M, alien)
	M.status_adjust(STAT_JITTERY, 5)

/datum/reagent/drink/milkshake/peanutshake
	name = REAGENT_PEANUTMILKSHAKE
	id = REAGENT_ID_PEANUTMILKSHAKE
	description = "Savory cream in an ice-cold stature."
	taste_description = "cold peanuts and cream"
	color = "#8e6f44"

	glass_name = REAGENT_PEANUTMILKSHAKE
	glass_desc = "Savory cream in an ice-cold stature."
	allergen_type = ALLERGEN_SEEDS|ALLERGEN_DAIRY //Made with peanutbutter(seeds) and dairy products
