/datum/reagent/soporific
	name = REAGENT_STOXIN
	id = REAGENT_ID_STOXIN
	scannable = SCANNABLE_ADVANCED
	description = "An effective hypnotic used to treat insomnia."
	taste_description = "bitterness"
	reagent_state = LIQUID
	color = "#009CA8"
	metabolism = REM * 0.5
	ingest_met = REM * 1.5
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/soporific
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	species_strength = alist(IS_SLIME = 0.15) // threshold ~1/6; evens to 3 as they are 'small' for flaps

/datum/reagent/soporific/affect_blood(mob/living/carbon/M, alien, removed)
	var/threshold = 1
	if(M.species.chem_strength_tox > 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
		threshold /= M.species.chem_strength_tox

	threshold *= species_mult(M)

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
