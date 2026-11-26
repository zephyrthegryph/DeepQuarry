// Overdoses of the drugs added by the chem rework (panacillin, iron saline, anticonvulsant, tercozolam). Families and the stage template: _pharmacology.dm.

/datum/affliction/overdose/panacillin
	name = "panacillin overdose"
	clinical_description = "Excess panacillin overwhelms the gut flora and loads the kidneys: nausea, dizziness and pallor, worse as the dose climbs."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 80,
		/datum/affliction_symptom/dizziness = 50,
		/datum/affliction_symptom/pallor    = 40,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_PANACILLIN = 30)
	caused_by_chems_organ = O_KIDNEYS

/datum/affliction/overdose/panacillin
	overdose_stage_data = list(
		list(list(/datum/affliction_symptom/nausea = 60), 1, 1),
		list(list(
			/datum/affliction_symptom/nausea    = 80,
			/datum/affliction_symptom/dizziness = 50,
		), 1, 2),
		list(list(
			/datum/affliction_symptom/nausea    = 95,
			/datum/affliction_symptom/dizziness = 70,
			/datum/affliction_symptom/pallor    = 60,
		), 2, 3),
	)

/datum/affliction/overdose/ironsaline
	name = "iron saline overdose"
	clinical_description = "Too much iron saline floods the blood with iron and fluid: nausea, fatigue and palpitations as the circulation is overloaded."
	symptom_pool = list(
		/datum/affliction_symptom/nausea       = 60,
		/datum/affliction_symptom/fatigue      = 60,
		/datum/affliction_symptom/palpitations = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_IRONSALINE = 60)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/ironsaline
	overdose_stage_data = list(
		list(list(/datum/affliction_symptom/pallor = 55), 1, 1),
		list(list(
			/datum/affliction_symptom/fatigue = 70,
			/datum/affliction_symptom/nausea  = 60,
		), 1, 2),
		list(list(
			/datum/affliction_symptom/fatigue      = 85,
			/datum/affliction_symptom/nausea       = 75,
			/datum/affliction_symptom/palpitations = 60,
		), 2, 3),
	)

/datum/affliction/overdose/anticonvulsant
	name = "anticonvulsant overdose"
	clinical_description = "An anticonvulsant overdose sedates the patient heavily: drowsiness, dizziness and confusion."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy    = 90,
		/datum/affliction_symptom/dizziness = 60,
		/datum/affliction_symptom/confusion = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_ANTICONVULSANT = 30)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/anticonvulsant
	overdose_stage_data = list(
		list(list(/datum/affliction_symptom/drowsy = 65), 1, 1),
		list(list(
			/datum/affliction_symptom/drowsy    = 85,
			/datum/affliction_symptom/dizziness = 55,
		), 1, 2),
		list(list(
			/datum/affliction_symptom/drowsy    = 100,
			/datum/affliction_symptom/dizziness = 75,
			/datum/affliction_symptom/confusion = 60,
		), 2, 3),
	)

/datum/affliction/overdose/tercozolam
	name = "tercozolam overdose"
	clinical_description = "Excess tercozolam leaves the patient drowsy, dizzy and confused."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy    = 80,
		/datum/affliction_symptom/dizziness = 60,
		/datum/affliction_symptom/confusion = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_TERCOZOLAM = 60)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/tercozolam
	overdose_stage_data = list(
		list(list(/datum/affliction_symptom/drowsy = 60), 1, 1),
		list(list(
			/datum/affliction_symptom/drowsy    = 80,
			/datum/affliction_symptom/dizziness = 55,
		), 1, 2),
		list(list(
			/datum/affliction_symptom/drowsy    = 95,
			/datum/affliction_symptom/dizziness = 70,
			/datum/affliction_symptom/confusion = 60,
		), 2, 3),
	)
