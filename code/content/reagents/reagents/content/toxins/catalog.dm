/datum/reagent/acid/polyacid
	name = REAGENT_PACID
	id = REAGENT_ID_PACID
	description = "Polytrinic acid is a an extremely corrosive chemical substance."
	taste_description = "acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#8E18A9"
	power = 10
	meltdose = 4
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY

/datum/reagent/acid/digestive
	name = REAGENT_STOMACID
	id = REAGENT_ID_STOMACID
	description = "Some form of digestive slurry."
	taste_description = "vomit"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#664330"
	power = 2
	meltdose = 30
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/acid/diet_digestive
	name = REAGENT_DIETSTOMACID
	id = REAGENT_ID_DIETSTOMACID
	description = "Some form of digestive slurry."
	taste_description = "vomit"
	reagent_state = LIQUID
	color = "#664330"
	power = 0.4
	meltdose = 150
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

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
