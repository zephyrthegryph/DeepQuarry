// Disease effects: afflictions that a /datum/affliction/contagion inflicts on its host.
//
// A disease that just "makes you sick" injures with plain INJURY_TOXIN (the
// generic toxic_poisoning affliction). The ones below have a distinctive
// presentation of their own, so the disease passes them as
// `injure(INJURY_TOXIN, x, affliction = ...)` and a medic reading the scanner
// sees the real root cause instead of anonymous "poisoning". All of them are
// injury_category TOXIC so they count toward toxic injury_load().

// --- Appendicitis ---------------------------------------------------------
// Bacterial toxins leaking from an inflamed appendix. Antitoxin only buys
// time; the cure is the appendectomy that ends the disease.
/datum/affliction/appendiceal_sepsis
	name = "appendiceal sepsis"
	category = "Abdominal"
	subcategory = "Infection"
	clinical_description = "Bacterial toxins seeping from an inflamed appendix into the abdominal cavity. Localised right-lower-quadrant pain, nausea and fever. Antitoxins and antimicrobials slow it; only removing the appendix resolves the source."
	injury_category = INJURY_CATEGORY_TOXIC
	progression_rate = 0
	pain_at_max = 60
	treated_by = list(TREAT_ANTIMICROBIAL = 1.0, TREAT_ANTITOXIN = 0.6, TREAT_DIGESTIVE = 0.8)
	symptom_pool = list(
		/datum/affliction_symptom/abdominal_tenderness = 95,
		/datum/affliction_symptom/nausea               = 80,
		/datum/affliction_symptom/fever_sensation      = 60,
		/datum/affliction_symptom/sharp_pain           = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
