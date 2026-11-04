// --- Revenant blight -------------------------------------------------------------
// A spectral wasting that drains the victim's vitality. Clears as the blight
// is cured (holy water / rest); antitoxin helps a little.
/datum/affliction/spectral_blight
	name = "spectral blight"
	category = "Infectious"
	subcategory = "Anomalous"
	clinical_description = "An anomalous wasting of unknown mechanism. Patients grow pale, cold and confused, as though something is drawing the life from them. Resting and holy water are anecdotally effective; antitoxins only slow it."
	injury_category = INJURY_CATEGORY_TOXIC
	progression_rate = 0
	consciousness_at_max = 40
	treated_by = list(TREAT_ANTITOXIN = 0.5)
	symptom_pool = list(
		/datum/affliction_symptom/pallor    = 90,
		/datum/affliction_symptom/chills    = 80,
		/datum/affliction_symptom/confusion = 60,
		/datum/affliction_symptom/fatigue   = 70,
	)
	min_symptoms = 2
	max_symptoms = 3
