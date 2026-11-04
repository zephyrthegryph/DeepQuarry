/datum/reagent/drink/tea/dyloteane
	treatment_tags = list(TREAT_ANTITOXIN = 0.15)
	name = REAGENT_DYLOTEANE
	id = REAGENT_ID_DYLOTEANE
	glass_name = "Medicinal tea cup"
	glass_desc = "Goes perfectly with alcohol poisoning!"
	taste_description = "The sweet taste of multidepartment cooperation!"
	cup_desc = "Goes perfectly with alcohol poisoning!"
	cup_name = "Medicinal tea cup"
	color = "#00FF00"

/datum/reagent/drink/tea/dyloteane
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/drink/tea/dyloteane/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.ingested)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 3)
	if(M.bloodstr)
		for(var/datum/reagent/R in M.bloodstr.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 10)

/datum/reagent/drink/tea/dyloteane
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/drink/tea/dyloteane/affect_ingest(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_DROWSY, -(6 * removed))
	M.status_adjust(STAT_HALLUCINATING, -(9 * removed))
