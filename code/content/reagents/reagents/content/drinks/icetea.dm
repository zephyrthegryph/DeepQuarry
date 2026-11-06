/datum/reagent/drink/tea/icetea
	name = REAGENT_ICETEA
	id = REAGENT_ID_ICETEA
	description = "No relation to a certain rap artist/ actor."
	taste_description = "sweet tea"
	color = "#AC7F24" // rgb: 16, 64, 56
	adj_temp = -5

	glass_name = "iced tea"
	glass_desc = "No relation to a certain rap artist/ actor."
	glass_special = list(DRINK_ICE)

	cup_icon_state = "cup_tea"
	cup_name = "iced tea"
	cup_desc = "No relation to a certain rap artist/ actor."

/datum/reagent/drink/tea/icetea
	species_chill = 0.5

/datum/reagent/drink/tea/icetea/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/tea/icetea/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	apply_species_chill(M, removed)

/datum/reagent/drink/tea/icetea/decaf
	name = REAGENT_ICETEADECAF
	id = REAGENT_ID_ICETEADECAF
	glass_name = "decaf iced tea"
	cup_name = "decaf iced tea"
	adj_dizzy = 0
	adj_drowsy = 0
	adj_sleepy = 0
	allergen_type = null
