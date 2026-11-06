/datum/reagent/claridyl/bloodburn
	treatment_tags = null
	name = REAGENT_BLOODBURN
	id = REAGENT_ID_BLOODBURN
	description = "A chemical used to soak up any reagents inside someones stomach, injection is not advised, if you need to ask why please seek a new job."
	taste_description = "liquid void"
	dermal_absorption = 0
	color = "#000000"
	metabolism = REM * 5
	// B19: a stomach-scouring agent, not a painkiller: none of claridyl's factors.
	factors = null
	species_factors = null
	immune_species_blood = 0

/datum/reagent/claridyl/bloodburn/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.bloodstr)//No seriously dont inject this wtf is wrong with you.
		for(var/datum/reagent/R in M.bloodstr.reagent_list)
			if(istype(R, /datum/reagent/blood))
				R.remove_self(removed * 15)

/datum/reagent/claridyl/bloodburn/affect_ingest(mob/living/carbon/M, alien, removed)
	if(M.ingested)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 5)
