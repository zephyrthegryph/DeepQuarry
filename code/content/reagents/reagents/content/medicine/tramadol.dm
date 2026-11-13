/datum/reagent/tramadol
	treatment_tags = list(TREAT_ANALGESIC = 1.0)
	factors = alist(STAT_ANALGESIA = 80, STAT_SEIZURE_PRONENESS = 5)
	species_factors = alist(IS_SLIME = alist(STAT_ANALGESIA = 64, STAT_SEIZURE_PRONENESS = 5, STAT_SLOWDOWN = 1, STAT_PENALTY_SCALE = 1.25))
	name = REAGENT_TRAMADOL
	id = REAGENT_ID_TRAMADOL
	description = "A strong painkiller for moderate to severe pain. Causes nausea (calcium carbonate settles it), lowers the seizure threshold, and is slightly addictive."
	taste_description = "sourness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#CB68FC"
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0.75
	scannable = SCANNABLE_BENEFICIAL
	metabolism = 0.02
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/tramadol/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_HALLUCINATING, 2)
