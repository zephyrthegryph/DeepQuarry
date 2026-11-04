/datum/reagent/drink/coffee/nukie/mega/high //Simultaneously makes you high and hungry
	name = REAGENT_NUKIEMEGAHIGH
	id = REAGENT_ID_NUKIEMEGAHIGH
	color = "#fafafa"
	taste_description = "moreishness, you could really go for a proper snack right now"

/datum/reagent/drink/coffee/nukie/mega/high
	species_strength = alist(IS_SLIME = 0.15) // threshold ~1/6

/datum/reagent/drink/coffee/nukie/mega/high/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	var/threshold = 1
	if(M.species.chem_strength_tox > 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
		threshold /= M.species.chem_strength_tox

	threshold *= species_mult(M)

	M.status_at_least(STAT_DRUGGED, 30)
	M.adjust_nutrition(-10 * removed)

	var/drug_strength = 20
	var/effective_dose = dose
	if(issmall(M)) effective_dose *= 2
	if(effective_dose < 1 * threshold)
		M.apply_effect(3, STUTTER)
		M.status_adjust(STAT_DIZZY, 5)
		if(prob(3))
			M.emote(pick("twitch", "giggle"))
	else if(effective_dose < 2 * threshold)
		M.apply_effect(3, STUTTER)
		M.status_adjust(STAT_JITTERY, 5)
		M.status_adjust(STAT_DIZZY, 5)
		M.status_at_least(STAT_DRUGGED, 35)
		M.status_at_least(STAT_HALLUCINATING, drug_strength * threshold)
		if(prob(5))
			M.emote(pick("twitch", "giggle"))
	else
		M.apply_effect(3, STUTTER)
		M.status_adjust(STAT_JITTERY, 10)
		M.status_adjust(STAT_DIZZY, 10)
		M.status_at_least(STAT_DRUGGED, 40)
		M.status_at_least(STAT_HALLUCINATING, drug_strength * threshold)
		if(prob(10))
			M.emote(pick("twitch", "giggle"))
