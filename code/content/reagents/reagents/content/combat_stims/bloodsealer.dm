/datum/reagent/bloodsealer
	factors = alist(STAT_STABILIZATION = 25)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_BLOODSEALER
	id = REAGENT_ID_BLOODSEALER
	description = "A strange chemical that will stablize bloodflow by burning the subject"
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#00BFFF"
	overdose = REAGENTS_OVERDOSE
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/bloodsealer
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/bloodsealer/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_BURN, 1 * removed, source = src) // the legacy negative burn-heal: a burn
