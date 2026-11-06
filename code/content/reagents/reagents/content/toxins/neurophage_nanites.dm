/datum/reagent/neurophage_nanites
	name = REAGENT_NEUROPHAGENANITES
	id = REAGENT_ID_NEUROPHAGENANITES
	scannable = SCANNABLE_SECRETIVE
	description = "Miniature medical robots that swiftly restore bodily damage. These ones seem to be completely hostile."
	taste_description = "metal"
	reagent_state = SOLID
	color = "#555555"
	metabolism = REM * 4
	filtered_organs = list(O_SPLEEN)
	affects_robots = TRUE
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/neurophage_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_NEURAL, 2 * removed, source = src)	// Their job is to give you a bad time.
	M.injure(INJURY_BLUNT, 2 * removed, source = src)
