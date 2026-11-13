/datum/reagent/panacillin
	// The broad antimicrobial: any infection, a little poisoning; slow, hard on the kidneys, and a long course leaves the patient nauseous
	// (/datum/affliction/nausea/panacillin). It weakens corophizine (/datum/affliction/chem_interaction/panacillin_corophizine).
	treatment_tags = list(TREAT_ANTIMICROBIAL = 0.8, TREAT_ANTITOXIN = 0.2)
	factors = alist(STAT_ANTIMICROBIAL = ANTIBIO_NORM)
	strains = alist(O_KIDNEYS = DRUG_STRAIN_MODERATE)
	name = REAGENT_PANACILLIN
	id = REAGENT_ID_PANACILLIN
	description = REAGENT_PANACILLIN + " is a broad-spectrum antimicrobial that works against any infection (bacterial, viral or wound), with a mild antitoxin action. It strains the kidneys, a long course leaves the patient nauseous for a while afterwards, and it weakens corophizine when the two are given together."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#D8D8F0"
	metabolism = REM * 0.25
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)
