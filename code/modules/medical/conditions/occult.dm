// Occult / arcane afflictions: signature effects of cult rituals and
// technomancer magic that deserve their own root cause on a scanner rather
// than anonymous poisoning or genetic damage.

// --- Flux sickness ------------------------------------------------------------
// Technomancer instability: raw arcane flux passing through living tissue.
// Instability's toxic and cellular backlash is routed here
// (injure(INJURY_TOXIN / INJURY_CELLULAR, x, affliction = /datum/affliction/flux_sickness)).
/datum/affliction/flux_sickness
	name = "flux sickness"
	category = "Anomalous"
	subcategory = "Arcane"
	clinical_description = "Exposure to an unstable, reality-bending energy field. Cells replicate erratically and the blood fills with metabolic debris. Presents like mild radiation sickness with a characteristic metallic taste and flickering vision. Antitoxins clear the debris; genetic repair reverses the cellular damage."
	injury_category = INJURY_CATEGORY_GENETIC
	progression_rate = 0
	consciousness_at_max = 30
	body_plans = BODY_PLAN_ALL
	simple_load_rate = 1
	treated_by = list(TREAT_GENETIC_REPAIR = 1.2, TREAT_ANTITOXIN = 0.8, TREAT_ANTIRADIATION = 0.4)
	symptom_pool = list(
		/datum/affliction_symptom/nausea              = 80,
		/datum/affliction_symptom/genetic_instability = 70,
		/datum/affliction_symptom/blurred_vision      = 60,
		/datum/affliction_symptom/fatigue             = 60,
		/datum/affliction_symptom/dizziness           = 50,
	)
	min_symptoms = 2
	max_symptoms = 4

// --- Profane corruption ---------------------------------------------------------
// What the cult's conversion rune pours into someone who resists it. The
// burning is ordinary burn trauma; this is the corruption itself. It fades on
// its own once the victim is off the rune.
/datum/affliction/profane_corruption
	name = "profane corruption"
	category = "Anomalous"
	subcategory = "Occult"
	clinical_description = "An unidentifiable contaminant saturating the blood and nervous system, accompanied by fever, auditory hallucinations and a pervasive sense of dread. It recedes slowly on its own once the source is removed; antitoxins hasten it."
	injury_category = INJURY_CATEGORY_TOXIC
	progression_rate = -2
	pain_at_max = 30
	body_plans = BODY_PLAN_ALL
	simple_load_rate = 0.5
	treated_by = list(TREAT_ANTITOXIN = 0.6)
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 85,
		/datum/affliction_symptom/confusion       = 70,
		/datum/affliction_symptom/headache        = 60,
		/datum/affliction_symptom/jittery         = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	spontaneous_emotes = list("twitch", "shiver")
	spontaneous_emote_prob = 3
