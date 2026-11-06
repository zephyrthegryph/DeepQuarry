/datum/reagent/toxin/mold
	name = REAGENT_MOLD
	id = REAGENT_ID_MOLD
	description = "A mold is a fungus that causes biodegradation of natural materials. This variant contains mycotoxins, and is dangerous to humans."
	taste_description = "mold"
	dermal_absorption = 0
	reagent_state = SOLID
	strength = 5
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/toxin/mold/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(prob(5))
		M.vomit()
