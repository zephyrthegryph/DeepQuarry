// Disease effects: afflictions that a /datum/disease inflicts on its host.
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
	treated_by = list(TREAT_ANTIMICROBIAL = 1.0, TREAT_ANTITOXIN = 0.6)
	symptom_pool = list(
		/datum/affliction_symptom/abdominal_tenderness = 95,
		/datum/affliction_symptom/nausea               = 80,
		/datum/affliction_symptom/fever_sensation      = 60,
		/datum/affliction_symptom/sharp_pain           = 50,
	)
	min_symptoms = 1
	max_symptoms = 3

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
