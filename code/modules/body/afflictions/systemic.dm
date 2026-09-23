// Systemic injury afflictions: what the humanoid plan turns non-located
// injuries into. Their presentation/treatment data lives with the rest of
// the medical content (medical/conditions/environmental.dm); this file owns
// how they plug into the body — injury category, vitals, and the body-level
// consequences of their severity.

// --- Acute pain (INJURY_PAIN) ---------------------------------------------------
// Stun weapons, agony, "halloss". Pure pain that fades on its own; enough of
// it knocks the patient out through the consciousness model.
/datum/affliction/acute_pain
	name = "acute pain"
	category = "Pain"
	clinical_description = "Overwhelming pain from a stunning blow, shock weapon or similar insult. Fades quickly on its own; painkillers speed recovery."
	injury_category = INJURY_CATEGORY_PAIN
	restoration_rate = 1
	biology = BIOLOGY_ALL
	// halloss 100 used to knock a baseline human out: severity 100 -> pain
	// 150 = tolerance (50) + 100 -> consciousness 0.
	pain_at_max = 150
	progression_rate = -8
	treated_by = list(TREAT_ANALGESIC = 1.5)
	min_symptoms = 0
	max_symptoms = 0

// --- Tissue hypoxia (oxygen debt) ------------------------------------------------------
// The body-side mirror of the physiology's oxygen debt
// (code/modules/body/physiology.dm): its severity IS the debt (capped at 100),
// set by the physiology every time the debt moves. It costs consciousness
// (unconscious at 50); the physiology grows the brain lesions.
/datum/affliction/tissue_hypoxia
	restoration_rate = 1
	consciousness_at_max = 200

/// Oxygenation pays the debt down; the physiology then re-syncs severity.
/datum/affliction/tissue_hypoxia/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(!body)
		return 0
	return body.pay_oxygen_debt(amount)

/// Severity follows the debt, never its own drift.
/datum/affliction/tissue_hypoxia/progress()
	pending_treatment = 0

// --- Toxic poisoning (INJURY_TOXIN) ----------------------------------------------------
/datum/affliction/toxic_poisoning
	injury_category = INJURY_CATEGORY_TOXIC
	restoration_rate = 1

// --- Genetic damage (INJURY_CELLULAR) ----------------------------------------------------
/datum/affliction/genetic_damage
	injury_category = INJURY_CATEGORY_GENETIC
	restoration_rate = 1
