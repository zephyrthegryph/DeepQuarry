/* Painkillers */

/datum/reagent/paracetamol
	treatment_tags = list(TREAT_ANALGESIC = 1.0)
	factors = alist(STAT_ANALGESIA = 25)
	species_factors = alist(IS_SLIME = alist(STAT_ANALGESIA = 18.75))
	name = REAGENT_PARACETAMOL
	id = REAGENT_ID_PARACETAMOL
	description = "Most probably know this as Tylenol, but this chemical is a mild, simple painkiller."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE * 2
	overdose_mod = 0.75
	scannable = SCANNABLE_BENEFICIAL
	metabolism = 0.02
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/paracetamol/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_HALLUCINATING, 2)
