/datum/reagent/ethylredoxrazine
	name = REAGENT_ETHYLREDOXRAZINE
	id = REAGENT_ID_ETHYLREDOXRAZINE
	description = "A powerful oxidizer that reacts with ethanol and sobers a drinker up. It leaves the patient confused, dizzy and slurring their words, and strains the liver mildly."
	taste_description = "bitterness"
	reagent_state = SOLID
	dermal_absorption = 0
	scannable = SCANNABLE_BENEFICIAL
	strains = alist(O_LIVER = DRUG_STRAIN_MILD)
	color = "#605048"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_RECDRUG

/datum/reagent/ethylredoxrazine
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/ethylredoxrazine/affect_ingest(mob/living/carbon/M, alien, removed)
	if(M.ingested)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 30)

/datum/reagent/ethylredoxrazine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/ethylredoxrazine/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.bloodstr)
		for(var/datum/reagent/R in M.bloodstr.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 20)
