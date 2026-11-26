/// Anticonvulsant: ends seizures and raises the threshold a shock must reach to cause one. Leaves the patient mildly drowsy, more so with adranol
/// (pharmacology/neurostimulants.dm).
/datum/reagent/anticonvulsant
	treatment_tags = list(TREAT_ANTICONVULSANT = 1.0)
	factors = alist(STAT_SEIZURE_PRONENESS = -10)
	name = REAGENT_ANTICONVULSANT
	id = REAGENT_ID_ANTICONVULSANT
	description = "Stops seizures and makes a patient far less prone to them. Leaves the patient mildly drowsy; together with adranol the drowsiness is heavier."
	taste_description = "chalky bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#c9d3e8"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
