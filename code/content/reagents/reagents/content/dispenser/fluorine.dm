/datum/reagent/fluorine
	name = REAGENT_FLUORINE
	id = REAGENT_ID_FLUORINE
	description = "A highly-reactive chemical element."
	taste_description = "acid"
	reagent_state = GAS
	scannable = SCANNABLE_ADVANCED
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/fluorine/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, removed, source = src)

/datum/reagent/fluorine/affect_touch(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, removed, source = src)
