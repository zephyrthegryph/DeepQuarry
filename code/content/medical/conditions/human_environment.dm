// Afflictions raised by a human's own Life() environment handling
// (code/modules/mob/living/carbon/human/life.dm): the tissue effects of a
// heavy radiation dose. The dose itself is the `radiation` metric (acute /
// chronic radiation sickness, environmental.dm); these are the injuries it
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

// --- Radiation poisoning -----------------------------------------------------
// The toxic load of cells dying en masse after a dose: metabolic debris the
// liver and kidneys can't keep up with. Routed here instead of generic toxic
// poisoning so scanners name the real cause.
/datum/affliction/radiation_poisoning
	name = "radiation poisoning"
	category = "Radiation"
	clinical_description = "Blood toxicity from widespread radiation-induced cell death. Nausea, vomiting, weakness and pallor that persist until the dose is purged. Antitoxins clear the debris; anti-radiation drugs stop more from forming."
	injury_category = INJURY_CATEGORY_TOXIC
	progression_rate = 0
	consciousness_at_max = 60
	treated_by = list(TREAT_ANTITOXIN = 1.2, TREAT_ANTIRADIATION = 0.8)
	symptom_pool = list(
		/datum/affliction_symptom/nausea            = 90,
		/datum/affliction_symptom/fatigue           = 80,
		/datum/affliction_symptom/pallor            = 70,
		/datum/affliction_symptom/radiation_reading = 90,
		/datum/affliction_symptom/dizziness         = 40,
	)
	min_symptoms = 2
	max_symptoms = 4
