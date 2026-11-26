/// A vasopressor that holds up blood pressure and cardiac output while the
/// cause is fixed. It supports perfusion; it treats nothing.
/datum/reagent/norepinephrine
	name = REAGENT_NOREPINEPHRINE
	id = REAGENT_ID_NOREPINEPHRINE
	description = REAGENT_NOREPINEPHRINE + " is a vasopressor. It tightens the blood vessels and drives the heart, holding up blood pressure and perfusion in shock until the cause is dealt with. It leaves the extremities numb."
	taste_description = "metal"
	reagent_state = LIQUID
	color = "#E05050"
	overdose = REAGENTS_OVERDOSE
	metabolism = REM * 0.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	factors = alist(STAT_CIRCULATION = 1.3, STAT_PUMP = 1.1, STAT_STABILIZATION = 10, STAT_HEART_RATE = 20, STAT_BP_SYSTOLIC = 20, STAT_BP_DIASTOLIC = 10)
	species_factors = alist(IS_DIONA = null)
	treatment_tags = list(TREAT_VASOPRESSOR = 0.6, TREAT_CIRCULATORY = 0.4)
