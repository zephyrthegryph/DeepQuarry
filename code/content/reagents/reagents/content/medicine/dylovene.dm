/datum/reagent/dylovene
	treatment_tags = list(TREAT_ANTITOXIN = 0.6)
	// It binds what is swallowed: while it is in the blood, a smaller share of every oral drug is absorbed.
	factors = alist(STAT_INGEST_ABSORPTION = 0.6)
	name = REAGENT_ANTITOXIN
	id = REAGENT_ID_ANTITOXIN
	description = REAGENT_ANTITOXIN + " is a broad-spectrum antitoxin: it treats poisoning and animal venoms. It binds swallowed drugs, so pills and drinks taken with it are absorbed poorly, and it makes the patient nauseous."
	taste_description = "a roll of gauze"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#00A000"
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_DYLO
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)
	species_strength = alist(IS_SLIME = 0.66)

/datum/reagent/dylovene/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_heal * species_mult(M)
	// Kept: a dose-gated status effect, not a factor or a strength.
	if(alien == IS_SLIME && dose >= 15)
		M.status_at_least(STAT_DRUGGED, 5)
	M.status_adjust(STAT_DROWSY, -(6 * removed * chem_effective))
	M.status_adjust(STAT_HALLUCINATING, -(9 * removed * chem_effective))
