/datum/reagent/arithrazine
	treatment_tags = list(TREAT_ANTIRADIATION = 1.0, TREAT_ANTITOXIN = 0.6)
	// Harsh on the tissues it protects: wounds and treatments work worse, and the stomach is strained.
	factors = alist(STAT_HEALING_RECEIVED = 0.7)
	strains = alist(O_STOMACH = DRUG_STRAIN_MODERATE)
	name = REAGENT_ARITHRAZINE
	id = REAGENT_ID_ARITHRAZINE
	description = REAGENT_ARITHRAZINE + " is an unstable medication used for the most extreme cases of radiation poisoning, with some antitoxin action. It slows the healing of wounds (every treatment received works worse), strains the stomach and is undone by rezadone."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#008000"
	metabolism = REM * 0.25
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 1.25
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG

/datum/reagent/arithrazine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/arithrazine/affect_blood(mob/living/carbon/M, alien, removed)
	// B14: radiation purge is the TREAT_ANTIRADIATION tag (purge_radiation()).
	// Its antitoxin action is in the treatment_tags profile.
	// Its harm is the stomach strain (strains) and the wound-healing malus (factors).
