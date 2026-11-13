
// === merged from medicine_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/reagent/adranol
	name = REAGENT_ADRANOL
	id = REAGENT_ID_ADRANOL
	description = "Clears confusion and blurred vision and cures choreomania. A bit of an overstimulant: it leaves the patient jittery and agitated, and mildly drowsy."
	taste_description = "milk"
	reagent_state = LIQUID
	dermal_absorption = 0.2 //Most medication has a much weaker effect as a patch.
	color = "#d5e2e5"
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/adranol
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/adranol/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.has_status(STAT_CONFUSED))
		M.status_at_least(STAT_CONFUSED, -8*removed)
	if(M.has_status(STAT_BLURRY))
		M.status_adjust(STAT_BLURRY, -(25*removed))
	// Jitter and drowsiness are its side effects (pharmacology/neurostimulants.dm), not something it treats.
