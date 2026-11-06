/datum/reagent/ethanol/bookwyrm
	name = REAGENT_BOOKWYRM
	id = REAGENT_ID_BOOKWYRM
	description = "You'd probably fancy a nice nap by the fireplace after drinking this."
	taste_description = "Mint, lime and a cold cozy nap"
	color = "#5678c3"
	strength = 20
	adj_temp = -10
	targ_temp = 273 //Dilluted cold front wont be the death of anyone who cant handle sipping liquid nitrogen.

	glass_name = REAGENT_BOOKWYRM
	glass_desc = "A cold lime mint drink. Dont drink to much or you might fall asleep."

/datum/reagent/ethanol/bookwyrm
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	// Slime evens to 3 due to the fact they are considered 'small' for flaps.
	species_strength = alist(IS_SKRELL = 1.2, IS_SLIME = 6)

/datum/reagent/ethanol/bookwyrm/affect_ingest(mob/living/carbon/M, alien, removed)
	var/threshold = species_mult(M)

	var/effective_dose = dose
	if(issmall(M))
		effective_dose *= 2

	if(effective_dose < 1 * threshold)
		if(effective_dose == metabolism * 2 || prob(5))
			M.emote("yawn")
	else if(effective_dose < 1.5 * threshold)
		M.status_at_least(STAT_BLURRY, 10)
	else if(effective_dose < 5 * threshold)
		if(prob(50))
			M.status_at_least(STAT_WEAKENED, 2)
		M.status_at_least(STAT_DROWSY, 20)
	else
		// Kept: a different symptom set, not a strength.
		if(alien == IS_SLIME) //They don't have eyes, and they don't really 'sleep'. Fumble their general senses.
			M.status_at_least(STAT_BLURRY, 30)
			if(prob(20))
				M.status_at_least(STAT_DEAFENED, 4)
				M.deaf_loop.start() // Ear Ringing/Deafness
				M.status_at_least(STAT_CONFUSED, 2)
			else
				M.status_at_least(STAT_WEAKENED, 2)
		else
			M.status_at_least(STAT_SLEEPING, 20)
		M.status_at_least(STAT_DROWSY, 60)
