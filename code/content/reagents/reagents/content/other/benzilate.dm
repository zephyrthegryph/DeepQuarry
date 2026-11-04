//YW stuff

/datum/reagent/benzilate
	name = REAGENT_BENZILATE
	id = REAGENT_ID_BENZILATE
	description = "Grey... goo? This smells like hot acid. Consuming this likely wouldn't be good for your health."
	taste_description = "raw iron"
	taste_mult = 0.4
	metabolism = REM * 2.5
	color = "#929292"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/benzilate
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	species_strength = alist(IS_SKRELL = 0.6)

/datum/reagent/benzilate/affect_blood(mob/living/carbon/M, alien, removed)
	var/drug_strength = 12 * species_mult(M)
	M.status_adjust(STAT_DIZZY, drug_strength)
	M.status_at_least(STAT_CONFUSED, drug_strength * 14)
