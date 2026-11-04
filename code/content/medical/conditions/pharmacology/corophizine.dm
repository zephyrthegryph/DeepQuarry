/datum/affliction/overdose/corophizine
	name = "corophizine overdose"
	clinical_description = "Corophizine at overdose is markedly more harsh than therapeutic dose — severe GI symptoms, liver irritation, and weakness."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 90,
		/datum/affliction_symptom/jaundice  = 50,
		/datum/affliction_symptom/fatigue   = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_COROPHIZINE = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/corophizine
	overdose_stage_data = list(
		list(list(
			/datum/affliction_symptom/nausea  = 70,
			/datum/affliction_symptom/fatigue = 45,
		), 1, 2),
		list(list(
			/datum/affliction_symptom/nausea   = 90,
			/datum/affliction_symptom/jaundice = 50,
			/datum/affliction_symptom/fatigue  = 60,
		), 2, 3),
		list(list(
			/datum/affliction_symptom/nausea               = 100,
			/datum/affliction_symptom/jaundice             = 75,
			/datum/affliction_symptom/fatigue              = 80,
			/datum/affliction_symptom/abdominal_tenderness = 55,
		), 3, 4, list("always_spawns" = list(/datum/affliction/toxic_poisoning))),
	)
