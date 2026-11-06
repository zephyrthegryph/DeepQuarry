//advanced crafting
//tier 1
/datum/reagent/souldew
	name = REAGENT_SOULDEW
	id = REAGENT_ID_SOULDEW
	description = "An experimental drug that solely works upon dead bodies"
	taste_description = "ash"
	reagent_state = LIQUID
	color = "#666699"
	scannable = 1
	overdose = REAGENTS_OVERDOSE * 2
	affects_dead = TRUE
	mrate_static = TRUE
	metabolism = 0.5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/souldew/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = 1 * M.species.chem_strength_heal
	if(M.stat == DEAD)
		// Only works on the dead, which a continuous tag can't express: mends directly.
		M.mend(TREAT_OXYGENATION, 3 * removed * chem_effective)
		M.mend(TREAT_TISSUE_REPAIR, 3 * removed * chem_effective)
		M.mend(TREAT_BURN_CARE, 3 * removed * chem_effective)
		M.mend(TREAT_ANTITOXIN, 3 * removed * chem_effective)
