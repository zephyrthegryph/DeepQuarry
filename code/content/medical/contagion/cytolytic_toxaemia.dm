// --- GBS ("gibbis") -----------------------------------------------------------
// A cytolytic agent that makes the body tear itself apart. Its toxic load is
// the prelude to the final-stage gib.
/datum/affliction/cytolytic_toxaemia
	name = "cytolytic toxaemia"
	category = "Infectious"
	subcategory = "Viral"
	clinical_description = "A viral cytolysin is dissolving cell membranes throughout the body. Profound weakness, pallor and internal pressure; if the agent is not cleared the tissues eventually fail catastrophically."
	injury_category = INJURY_CATEGORY_TOXIC
	progression_rate = 0
	pain_at_max = 40
	consciousness_at_max = 30
	treated_by = list(TREAT_ANTITOXIN = 0.8, TREAT_GENETIC_REPAIR = 0.5)
	symptom_pool = list(
		/datum/affliction_symptom/fatigue           = 90,
		/datum/affliction_symptom/limb_weakness     = 70,
		/datum/affliction_symptom/pallor            = 70,
		/datum/affliction_symptom/internal_pressure = 60,
	)
	min_symptoms = 2
	max_symptoms = 4
