/datum/reagent/tricordrazine
	// The generic: weak at everything a field medic meets, and hard on the liver; mildly addictive (GLOB.reagent_addictive_slow).
	treatment_tags = list(
		TREAT_HEMOSTATIC = 0.3,
		TREAT_TISSUE_REPAIR = 0.4,
		TREAT_BURN_CARE = 0.3,
		TREAT_ANTITOXIN = 0.3,
		TREAT_OXYGENATION = 0.3,
	)
	strains = alist(O_LIVER = DRUG_STRAIN_MODERATE)
	name = REAGENT_TRICORDRAZINE
	id = REAGENT_ID_TRICORDRAZINE
	description = REAGENT_TRICORDRAZINE + " is a highly potent stimulant, originally derived from cordrazine. A weak generic: it treats low-grade tissue damage (bleeding included), burns, poisoning and oxygen starvation at once, so it works when nothing is diagnosed, but a specialist drug does each job better. It strains the liver, is mildly addictive, and an overdose is severely toxic."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8040FF"
	overdose = REAGENTS_OVERDOSE * 4 // TRICORD FUCKING KILLS YOU
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_TRICORD

/datum/reagent/tricordrazine/overdose(mob/living/carbon/M, alien, removed)
	..()
	M.status_at_least(STAT_DRUGGED, 5)
	M.status_at_least(STAT_CONFUSED, 5)
