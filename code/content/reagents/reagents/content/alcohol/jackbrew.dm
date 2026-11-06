/datum/reagent/ethanol/coffee/jackbrew
	factors = alist(STAT_SLOWDOWN = -1, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_JACKBREW
	id = REAGENT_ID_JACKBREW
	description = "Irish coffee, and hyperzine. A common mix for panicked drinkers, EMTS, Paramedics, and CMOs alone on the job."
	taste_description = "wishing you could give up on the day"
	color = "#4C3100"
	strength = 15

	glass_name = REAGENT_JACKBREW
	glass_desc = "Irish coffee, and hyperzine. A common mix for panicked drinkers, EMTS, Paramedics, and CMOs alone on the job."

/datum/reagent/ethanol/coffee/jackbrew
	species_strength = alist(IS_TAJARA = 1.25)

/datum/reagent/ethanol/coffee/jackbrew/affect_ingest(mob/living/carbon/M, alien, removed)
	removed *= species_mult(M)
	// Kept: a species-only, dose-gated status/nutrition side effect.
	if(alien == IS_SLIME)
		M.status_adjust(STAT_JITTERY, 4) //Hyperactive fluid pumping results in unstable 'skeleton', resulting in vibration.
		if(dose >= 5)
			M.set_nutrition((nutrition_of(M) - (removed * 2))) //Sadly this movement starts burning food in higher doses.
	..()
	if(prob(5))
		M.emote(pick("twitch", "blink_r", "shiver", "weh", "weh", "weh")) // weh - Jack
