// --- Beesease -----------------------------------------------------------------
// Apid larvae stinging the stomach lining from the inside.
/datum/affliction/apid_infestation
	name = "apid infestation"
	category = "Infectious"
	subcategory = "Parasitic"
	clinical_description = "Apid larvae nesting in the stomach, stinging its lining and releasing venom into the gut. Buzzing abdominal discomfort and nausea; clears with the infestation."
	injury_category = INJURY_CATEGORY_TOXIC
	progression_rate = -0.5
	pain_at_max = 50
	treated_by = list(TREAT_ANTITOXIN = 1.2)
	symptom_pool = list(
		/datum/affliction_symptom/abdominal_tenderness = 80,
		/datum/affliction_symptom/nausea               = 70,
		/datum/affliction_symptom/internal_pressure    = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
