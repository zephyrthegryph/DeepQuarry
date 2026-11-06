/datum/reagent/eden/snake
	name = REAGENT_EDENSNAKE
	id = REAGENT_ID_EDENSNAKE
	metabolism = 0.1
	description = "It used to be an anti toxin until it was tainted."
	taste_description = "hellfire"
	color = "#FF0000"
	immune_species_blood = 0

/datum/reagent/eden/snake/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure_many(alist(INJURY_BURN = 1, INJURY_BLUNT = 1, INJURY_TOXIN = 1), source = src)
	M.AdjustLosebreath(1) // The taint chokes.
