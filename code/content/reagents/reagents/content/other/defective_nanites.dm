// The opposite to healing nanites, exists to make unidentified hypos implied to have nanites not be 100% safe.
/datum/reagent/defective_nanites
	name = REAGENT_DEFECTIVENANITES
	id = REAGENT_ID_DEFECTIVENANITES
	scannable = SCANNABLE_DIFFICULT
	description = "Miniature medical robots that are malfunctioning and cause bodily harm. Fortunately, they cannot self-replicate."
	taste_description = "metal"
	reagent_state = SOLID
	dermal_absorption = 0.1 //Burrow into the skin and get into your bloodstream. This means 60u splashed on someone (with no losses, given splash is lossy) will give them 6u of nanites.
	color = "#333333"
	metabolism = REM * 3 // Broken nanomachines go a bit slower.
	scannable = 1
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD
	// Clog the lungs' exchange surfaces.
	factors = alist(STAT_GAS_EXCHANGE = 0.5)

/datum/reagent/defective_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure_many(alist(
		INJURY_BLUNT = 2 * removed,
		INJURY_BURN = 2 * removed,
		INJURY_TOXIN = 2 * removed,
		INJURY_CELLULAR = 2 * removed,
	), source = src)
