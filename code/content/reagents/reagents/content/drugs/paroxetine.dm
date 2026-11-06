/datum/reagent/drugs/paroxetine
	name = REAGENT_PAROXETINE
	id = REAGENT_ID_PAROXETINE
	description = "Stabilizes the mind greatly, but has a chance of adverse effects."
	taste_description = "mild oranges"
	color = "#FF80BF"
	scannable = SCANNABLE_BENEFICIAL
	high_message_list = list("Everything feels good, stable.", "You feel grounded.")
	sober_message_list = list("The stability is gone...", "Everything is much less stable.")
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/drugs/paroxetine/affect_blood(mob/living/carbon/M, alien, removed)
	..()

	M.status_set(STAT_FEAR, max((M.status_units(STAT_FEAR) - 6),0))
	if(prob(5) && prob_proc == TRUE)
		to_chat(M, span_warning("Everything feels out of control..."))
		M.status_adjust(STAT_HALLUCINATING, 200)
		prob_proc = FALSE
