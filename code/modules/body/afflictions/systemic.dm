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

// --- Tissue hypoxia (INJURY_ASPHYXIA) -------------------------------------------------
/datum/affliction/tissue_hypoxia
	injury_category = INJURY_CATEGORY_ASPHYXIA
	restoration_rate = 1
	// Unconscious at severity 50 (the old "oxyloss > maxHealth/2" rule).
	consciousness_at_max = 200

/// Anoxic brain injury: nothing below DQ_HYPOXIA_BRAIN_DAMAGE, ramping to
/// DQ_HYPOXIA_BRAIN_RATE per tick at severity 100. Suffocation kills through
/// the brain — organ death — not through a number running out.
/datum/affliction/tissue_hypoxia/tick()
	..()
	if(QDELETED(src) || severity < DQ_HYPOXIA_BRAIN_DAMAGE || !ishuman(owner))
		return
	var/mob/living/carbon/human/H = owner
	if(!H.should_have_organ(O_BRAIN))
		return
	var/rate = DQ_HYPOXIA_BRAIN_RATE * (severity - DQ_HYPOXIA_BRAIN_DAMAGE) / (AFFLICTION_SEVERITY_TERMINAL - DQ_HYPOXIA_BRAIN_DAMAGE)
	if(H.factor(BF_STABILIZATION))
		rate *= 0.5
	H.injure(INJURY_NEURAL, rate, source = src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

// --- Toxic poisoning (INJURY_TOXIN) ----------------------------------------------------
/datum/affliction/toxic_poisoning
	injury_category = INJURY_CATEGORY_TOXIC
	restoration_rate = 1

// --- Genetic damage (INJURY_CELLULAR) ----------------------------------------------------
/datum/affliction/genetic_damage
	injury_category = INJURY_CATEGORY_GENETIC
	restoration_rate = 1
