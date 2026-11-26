/datum/reagent/cordradaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/cordradaxon
	treatment_tags = list(TREAT_CARDIAC = 1.0, TREAT_OXYGENATION = 0.6)
	// Repairs the heart and settles arrhythmia, at the cost of a lower blood pressure; the repaired rhythm reads as a regular one on a scan.
	factors = alist(STAT_BP_SYSTOLIC = -10, STAT_BP_DIASTOLIC = -6)
	hides = list(HIDE_PULSE_IRREGULAR)
	name = REAGENT_CORDRADAXON
	id = REAGENT_ID_CORDRADAXON
	description = "Used to repair the heart and the specialized tissues of the circulatory system, and to settle an arrhythmia. It lowers blood pressure while it is in the blood, and it hides an irregular pulse from instruments, so a patient on it can look steadier than they are."
	taste_description = "rust"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FF4444"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/cordradaxon, daxon_organs, list(O_HEART, O_SPLEEN, O_RESPONSE, O_ANCHOR, O_EGG))

TYPE_TABLE(/datum/reagent/cordradaxon, daxon_partners, list(REAGENT_ID_HYRONALIN, REAGENT_ID_PERIDAXON))

/datum/reagent/cordradaxon/daxon_clash(mob/living/carbon/human/H, removed)
	H.set_losebreath(CLAMP(H.losebreath() + 1, 0, 10))
