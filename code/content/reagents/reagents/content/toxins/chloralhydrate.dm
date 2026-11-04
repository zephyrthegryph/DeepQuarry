/datum/reagent/chloralhydrate
	name = REAGENT_CHLORALHYDRATE
	id = REAGENT_ID_CHLORALHYDRATE
	scannable = SCANNABLE_ADVANCED
	description = "A powerful sedative."
	taste_description = "bitterness"
	reagent_state = SOLID
	color = "#000067"
	metabolism = REM * 0.5
	ingest_met = REM * 1.5
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 2	//For that good, lethal feeling // Reduced with overdose changes. Slightly stronger than before
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/chloralhydrate
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	species_strength = alist(IS_SLIME = 0.15) // threshold ~1/6

/datum/reagent/chloralhydrate/affect_blood(mob/living/carbon/M, alien, removed)
	var/threshold = 1
	if(M.species.chem_strength_tox > 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
		threshold /= M.species.chem_strength_tox

	threshold *= species_mult(M)

	var/effective_dose = dose
	if(issmall(M))
		effective_dose *= 2

	if(effective_dose == metabolism)
		M.status_at_least(STAT_CONFUSED, 2)
		M.status_adjust(STAT_DROWSY, 2)
	else if(effective_dose < 2 * threshold)
		M.status_at_least(STAT_WEAKENED, 30)
		M.status_at_least(STAT_BLURRY, 10)
	else
		// Kept: a different symptom set, not a strength.
		if(alien == IS_SLIME)
			if(prob(30))
				M.status_at_least(STAT_DEAFENED, 4)
				M.deaf_loop.start() // Ear Ringing/Deafness
			M.status_at_least(STAT_BLURRY, 60)
			M.status_at_least(STAT_WEAKENED, 30)
			M.status_at_least(STAT_CONFUSED, 40)
		else
			M.status_at_least(STAT_SLEEPING, 30)

	if(effective_dose > 1 * threshold)
		M.injure(INJURY_TOXIN, removed, source = src)

/datum/reagent/chloralhydrate/overdose(mob/living/carbon/M, alien, removed)
	..()
	M.SetLosebreath(10) // Respiratory depression: no breaths are drawn.

/datum/reagent/chloralhydrate/beer2 //disguised as normal beer for use by emagged brobots
	name = REAGENT_BEER2
	id = REAGENT_ID_BEER2
	scannable = SCANNABLE_SECRETIVE
	description = "An alcoholic beverage made from malted grains, hops, yeast, and water. The fermentation appears to be incomplete." //If the players manage to analyze this, they deserve to know something is wrong.
	taste_description = "beer"
	reagent_state = LIQUID
	color = "#FFD300"

	glass_name = REAGENT_ID_BEER
	glass_desc = "A freezing pint of beer"
	wiki_flag = WIKI_SPOILER
