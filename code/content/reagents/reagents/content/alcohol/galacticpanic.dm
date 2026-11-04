/datum/reagent/ethanol/galacticpanic
	name = REAGENT_GALACTICPANIC
	id = REAGENT_ID_GALACTICPANIC
	description = "The absolute worst thing you could ever put in your body."
	taste_description = "an entire galaxy collasping in on itself"
	strength = 10
	druggy = 50
	halluci = 30
	color = "#d3785d"

	glass_name = REAGENT_GALACTICPANIC
	glass_desc = "Looking into this is like staring at the stars."

/datum/reagent/ethanol/galacticpanic/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.status_at_least(STAT_STUNNED, 2)

	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		if(dose * strength >= strength) // Early warning
			M.status_adjust(STAT_DIZZY, 24) // Intentionally higher than normal to compensate for it's previous effects.
		if(dose * strength >= strength * 2.5) // Slurring takes longer. Again, intentional.
			M.status_at_least(STAT_SLURRING, 30)
