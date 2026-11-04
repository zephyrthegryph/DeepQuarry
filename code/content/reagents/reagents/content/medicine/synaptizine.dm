/* Other medicine */

/datum/reagent/synaptizine
	treatment_tags = list(TREAT_NEURAL_REPAIR = 1.0)
	factors = alist(STAT_ANALGESIA = 20)
	species_factors = alist(IS_DIONA = null, IS_SLIME = alist(STAT_ANALGESIA = 10))
	name = REAGENT_SYNAPTIZINE
	id = REAGENT_ID_SYNAPTIZINE
	description = REAGENT_SYNAPTIZINE + " is used to treat various diseases."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#99CCFF"
	metabolism = REM * 0.05
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/synaptizine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/synaptizine/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_heal * species_mult(M)
	// Kept: a species-only, dose-gated regeneration burst.
	if(alien == IS_SLIME)
		if(dose >= 5) //Not effective in small doses, though it causes toxins at higher ones, it will make the regeneration for brute and burn more 'efficient' at the cost of more nutrition.
			// Species-specific dose-gated regeneration boost: mends directly.
			M.adjust_nutrition(removed * 2)
			M.mend(TREAT_TISSUE_REPAIR, 2 * removed)
			M.mend(TREAT_BURN_CARE, 1 * removed)
	M.status_adjust(STAT_DROWSY, -5)
	M.status_adjust(STAT_PARALYZED, -1)
	M.status_adjust(STAT_STUNNED, -1)
	M.status_adjust(STAT_WEAKENED, -1)
	holder.remove_reagent(REAGENT_ID_MINDBREAKER, 5)
	M.status_adjust(STAT_HALLUCINATING, -10)
	M.injure(INJURY_TOXIN, 10 * removed * chem_effective, source = src) // It used to be incredibly deadly due to an oversight. Not anymore!
