// Ryetalyn's genetic repair is its treatment_tags profile. It is for genetic damage, not resetting mutations (breaks traitgenes).

/*/datum/reagent/hyperzine
	name = REAGENT_HYPERZINE
	id = REAGENT_ID_HYPERZINE
	description = "Hyperzine is a highly effective, long lasting, muscle stimulant."
	reagent_state = LIQUID
	color = "#FF3300"
	metabolism = REM * 1
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE * 0.5

/datum/reagent/hyperzine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/hyperzine/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(5))
		M.emote(pick("twitch", "blink_r", "shiver"))
*/
/datum/reagent/ethylredoxrazine
	name = REAGENT_ETHYLREDOXRAZINE
	id = REAGENT_ID_ETHYLREDOXRAZINE
	description = "A powerful oxidizer that reacts with ethanol."
	taste_description = "bitterness"
	reagent_state = SOLID
	dermal_absorption = 0
	scannable = SCANNABLE_BENEFICIAL
	color = "#605048"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_RECDRUG

/datum/reagent/ethylredoxrazine
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/ethylredoxrazine/affect_ingest(mob/living/carbon/M, alien, removed)
	M.status_end(STAT_DIZZY)
	M.status_set(STAT_DROWSY, 0)
	M.status_set(STAT_STUTTERING, 0)
	M.status_set(STAT_CONFUSED, 0)
	if(M.ingested)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 30)

/datum/reagent/ethylredoxrazine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/ethylredoxrazine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_end(STAT_DIZZY)
	M.status_set(STAT_DROWSY, 0)
	M.status_set(STAT_STUTTERING, 0)
	M.status_set(STAT_CONFUSED, 0)
	if(M.bloodstr)
		for(var/datum/reagent/R in M.bloodstr.reagent_list)
			if(istype(R, /datum/reagent/ethanol))
				R.remove_self(removed * 20)
