/datum/reagent/capsaicin
	name = REAGENT_CAPSAICIN
	id = REAGENT_ID_CAPSAICIN
	description = "This is what makes chilis hot."
	taste_description = "hot peppers"
	taste_mult = 1.5
	reagent_state = LIQUID
	ingest_met = REM
	color = "#B31008"
	cup_prefix = "hot"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/capsaicin
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/capsaicin/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 0.5 * removed, source = src)

/datum/reagent/capsaicin/affect_ingest(mob/living/carbon/M, alien, removed)
	// Do not call parent, we don't want this absorbed into our bloodstream!
	handle_spicy(M, alien, removed)
