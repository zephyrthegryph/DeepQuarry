/datum/reagent/irradiated_nanites
	name = REAGENT_IRRADIATEDNANITES
	id = REAGENT_ID_IRRADIATEDNANITES
	scannable = SCANNABLE_SECRETIVE
	description = "Miniature medical robots that swiftly restore bodily damage. These ones seem to be malfunctioning."
	taste_description = "metal"
	reagent_state = SOLID
	color = "#555555"
	metabolism = REM * 4
	affects_robots = TRUE
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/irradiated_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	//SSradiation.radiate(get_turf(M), 20)	// Irradiate people around you. //TODO
	M.add_radiation(5 * removed)	// Irradiate you. Because it's inside you.
