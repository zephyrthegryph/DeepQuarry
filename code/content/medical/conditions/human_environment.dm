// Afflictions raised by a human's own Life() environment handling
// (code/modules/mob/living/carbon/human/life.dm): the tissue effects of a
// heavy radiation dose. The dose itself is the `radiation` metric (radiation
// sickness, environmental.dm); these are the injuries it
// leaves behind.

// --- Radiation burns --------------------------------------------------------
// Beta burns: skin on a limb reddens, blisters and sloughs days early from a
// massive dose. Located on the limb it appeared on
// (injure(INJURY_BURN, x, limb, affliction = /datum/affliction/radiation_burns)).
// Heals slowly on its own; burn care and anti-radiation drugs speed it.
/datum/affliction/radiation_burns
	name = "radiation burns"
	category = "Radiation"
	clinical_description = "Deep erythema, blistering and moist desquamation over a limb, without any history of heat or flame — the skin was killed from within by an extreme radiation dose. Painful and slow to heal; treat as a burn while the dose is cleared."
	injury_category = INJURY_CATEGORY_THERMAL
	progression_rate = -0.5
	pain_at_max = 60
	consciousness_at_max = 20
	treated_by = list(TREAT_BURN_CARE = 1.2, TREAT_ANTIRADIATION = 0.5)
	symptom_pool = list(
		/datum/affliction_symptom/skin_burns_minor  = 95,
		/datum/affliction_symptom/burning_limb      = 70,
		/datum/affliction_symptom/radiation_reading = 80,
	)
	min_symptoms = 1
	max_symptoms = 3
