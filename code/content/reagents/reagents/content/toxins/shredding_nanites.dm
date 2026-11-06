/*
 * Hostile nanomachines.
 * Unscannable, and commonly all look the same.
 */

/datum/reagent/shredding_nanites
	name = REAGENT_SHREDDINGNANITES
	id = REAGENT_ID_SHREDDINGNANITES
	scannable = SCANNABLE_SECRETIVE
	description = "Miniature medical robots that swiftly restore bodily damage. These ones seem to be malfunctioning."
	taste_description = "metal"
	reagent_state = SOLID
	color = "#555555"
	metabolism = REM * 4 // Nanomachines. Fast.
	affects_robots = TRUE
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD
	// They shred the alveoli too.
	factors = alist(STAT_GAS_EXCHANGE = 0.4)

/datum/reagent/shredding_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_CUT, 4 * removed, source = src)
