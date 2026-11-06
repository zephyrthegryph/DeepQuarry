/datum/affliction/overdose/spaceacillin
	name = "spaceacillin overdose"
	clinical_description = "Spaceacillin overdose produces broad GI disturbance and mild liver stress."
	symptom_pool = list(
		/datum/affliction_symptom/nausea  = 70,
		/datum/affliction_symptom/fatigue = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_SPACEACILLIN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/spaceacillin
	overdose_stage_data = list(
		list(list(/datum/affliction_symptom/nausea = 55), 1, 1),
		list(list(
			/datum/affliction_symptom/nausea  = 75,
			/datum/affliction_symptom/fatigue = 50,
		), 1, 2),
		list(list(
			/datum/affliction_symptom/nausea   = 90,
			/datum/affliction_symptom/fatigue  = 75,
			/datum/affliction_symptom/jaundice = 55,
		), 2, 3, list("always_spawns" = list(/datum/affliction/toxic_poisoning))),
	)
