// Panacillin: the nausea a course leaves behind and the clash with corophizine. Families and the stage template: _pharmacology.dm.

/// Climbs while more than the threshold of panacillin is in the blood (a course), and fades slowly after it clears (chem_scaling lingers).
/datum/affliction/nausea/panacillin
	name = "panacillin nausea"
	clinical_description = "A long course of panacillin sours the stomach. The nausea builds while a lot of the drug is in the blood and lingers for a while after it has cleared; calcium carbonate settles it sooner."
	progression_rate = 0
	chem_scaling = TRUE
	chem_climb_per_unit = 0.2
	chem_decay_per_tick = 1
	caused_by_chems = list(REAGENT_ID_PANACILLIN = 8)
	caused_by_chems_organ = O_STOMACH

/// The scaling dispatcher drives a stage by severity (_dq_apply_od_stage): the same Mild, Severe and Critical table an overdose uses.
TYPE_TABLE(/datum/affliction/nausea/panacillin, affliction_stages, overdose_stages( \
	chem_stage(list(/datum/affliction_symptom/nausea = 60), 1, 1), \
	chem_stage(list(/datum/affliction_symptom/nausea = 80, /datum/affliction_symptom/dizziness = 30), 1, 2), \
	chem_stage(list(/datum/affliction_symptom/nausea = 100, /datum/affliction_symptom/dizziness = 50, /datum/affliction_symptom/pallor = 30), 2, 3), \
))

/datum/affliction/chem_interaction/panacillin_corophizine
	name = "antibiotic competition"
	clinical_description = "Panacillin occupies the bacterial targets corophizine needs; given together, corophizine works at half strength."
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_COROPHIZINE = 0.5)
	caused_by_chems = list(
		REAGENT_ID_PANACILLIN  = 2,
		REAGENT_ID_COROPHIZINE = 2,
	)
	caused_by_chems_organ = O_LIVER
