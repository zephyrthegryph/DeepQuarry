/datum/reagent/drugs/psilocybin
	name = REAGENT_PSILOCYBIN
	id = REAGENT_ID_PSILOCYBIN
	description = "A strong psycotropic derived from certain species of mushroom."
	taste_description = "mushroom"
	color = "#E700E7"
	high_message_list = list("The world distorts around you...!",
	"The walls look like they're moving...",
	"Nothing really makes sense right now.",
	"It feels like you've melded with the world around you...")
	sober_message_list = list("Everything feels... flat.", "You feel almost TOO grounded in your surroundings.")
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED // bonus
	industrial_use = REFINERYEXPORT_REASON_ILLDRUG

/datum/reagent/drugs/psilocybin/affect_blood(mob/living/carbon/M, alien, removed)
	..()

	var/threshold = 1
	if(M.species.chem_strength_tox > 0) //Closer to 0 means they're more resistant to toxins. Higher than 1 means they're weaker to toxins.
		threshold /= M.species.chem_strength_tox

	threshold *= species_mult(M)

	M.status_at_least(STAT_DRUGGED, 30)

	var/drug_strength = 20
	var/effective_dose = dose
	if(issmall(M)) effective_dose *= 2
	if(effective_dose < 1 * threshold)
		M.apply_effect(3, STUTTER)
		M.status_adjust(STAT_DIZZY, 5)
		if(prob(3) && prob_proc == TRUE)
			M.emote(pick("twitch", "giggle"))
			prob_proc = FALSE
	else if(effective_dose < 2 * threshold)
		M.apply_effect(3, STUTTER)
		M.status_adjust(STAT_JITTERY, 5)
		M.status_adjust(STAT_DIZZY, 5)
		M.status_at_least(STAT_DRUGGED, 35)
		M.status_at_least(STAT_HALLUCINATING, drug_strength * threshold)
		if(prob(5) && prob_proc == TRUE)
			M.emote(pick("twitch", "giggle"))
			prob_proc = FALSE
	else
		M.apply_effect(3, STUTTER)
		M.status_adjust(STAT_JITTERY, 10)
		M.status_adjust(STAT_DIZZY, 10)
		M.status_at_least(STAT_DRUGGED, 40)
		M.status_at_least(STAT_HALLUCINATING, drug_strength * threshold)
		if(prob(10) && prob_proc == TRUE)
			M.emote(pick("twitch", "giggle"))
			prob_proc = FALSE
