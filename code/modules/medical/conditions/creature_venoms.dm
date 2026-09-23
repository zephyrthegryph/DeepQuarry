// Creature venoms, stings and feeding injuries.
//
// Distinctive harms dealt directly by simple mobs (not by a reagent they
// inject — reagents own their own effects). Each is passed as
// `affliction =` to injure() by the creature responsible, so a medic sees
// "cnidarian envenomation" rather than a generic poisoning, and treats it by
// mechanism. All are systemic (injure with a systemic kind and zone = null).
//
// On the simple body plan a non-load affliction still counts its severity
// toward the creature's total load, so a venom works as a damage-over-time
// on animals too. Pure pain venoms opt out (simple creatures fight through
// pain, exactly as the old halloss did nothing to simple_mob health).

/datum/affliction/venom
	name = "envenomation"
	category = "Toxic"
	subcategory = "Venom"
	injury_category = INJURY_CATEGORY_TOXIC
	biology = BIOLOGY_ORGANIC
	// Venom works on any living creature, not just patients: on a simple
	// body it keeps dealing toxin load while it lasts.
	body_plans = BODY_PLAN_ALL
	simple_load_rate = 1
	/// If FALSE this venom is felt, not suffered: it contributes nothing to a
	/// simple creature's injury load.
	var/counts_on_simple_bodies = TRUE

/datum/affliction/venom/load_value()
	if(!counts_on_simple_bodies && istype(body, /datum/body/simple))
		return 0
	return ..()


// --- Neurotoxic sting (succlets) ---------------------------------------------------
// A sting that floods the nerves: searing pain, hallucinations, and a slow
// systemic poisoning. Fades on its own; antitoxin clears it, painkillers blunt it.
/datum/affliction/venom/neurotoxic_sting
	name = "neurotoxic envenomation"
	clinical_description = "A neurotoxic sting overstimulating the peripheral nerves. Intense burning pain radiating from the sting site, tremor and perceptual disturbance, with a mild systemic toxic load. Self-limiting; antitoxin clears the venom and analgesics control the pain."
	progression_rate = -2
	pain_at_max = 120
	treated_by = list(TREAT_ANTITOXIN = 1.5, TREAT_ANALGESIC = 0.5)
	symptom_pool = list(
		/datum/affliction_symptom/sharp_pain = 90,
		/datum/affliction_symptom/jittery    = 60,
		/datum/affliction_symptom/confusion  = 40,
		/datum/affliction_symptom/nausea     = 30,
	)
	min_symptoms = 1
	max_symptoms = 3


// --- Cnidarian sting (space jellyfish) --------------------------------------------------
// Nematocyst venom: agonising welts and numbness, no lasting harm.
/datum/affliction/venom/cnidarian_sting
	name = "cnidarian envenomation"
	clinical_description = "Nematocyst venom from a jellyfish-like organism. Burning, throbbing pain and patchy numbness; not dangerous in itself and fades quickly. Analgesics help."
	injury_category = INJURY_CATEGORY_PAIN
	progression_rate = -6
	pain_at_max = 150
	counts_on_simple_bodies = FALSE
	treated_by = list(TREAT_ANALGESIC = 1.5, TREAT_ANTITOXIN = 0.5)
	symptom_pool = list(
		/datum/affliction_symptom/skin_burns_minor = 85,
		/datum/affliction_symptom/burning_limb   = 80,
		/datum/affliction_symptom/throbbing_pain = 70,
		/datum/affliction_symptom/numbness_arm   = 40,
		/datum/affliction_symptom/numbness_leg   = 40,
	)
	min_symptoms = 1
	max_symptoms = 2


// --- Spore irritation (sif moths) --------------------------------------------------------
// Irritant spores lodged in the airway and eyes: coughing, streaming eyes and
// pain that clears as the spores are expelled.
/datum/affliction/venom/spore_irritation
	name = "spore irritation"
	subcategory = "Irritant"
	clinical_description = "Inhaled irritant spores inflaming the airway and mucous membranes. Painful coughing and wheezing, blurred vision. Clears as the spores are expelled; analgesics and antitoxin speed recovery."
	injury_category = INJURY_CATEGORY_PAIN
	progression_rate = -5
	pain_at_max = 120
	counts_on_simple_bodies = FALSE
	treated_by = list(TREAT_ANALGESIC = 1, TREAT_ANTITOXIN = 1, TREAT_RESPIRATORY = 1)
	symptom_pool = list(
		/datum/affliction_symptom/wet_cough     = 80,
		/datum/affliction_symptom/wheeze        = 60,
		/datum/affliction_symptom/blurred_vision = 50,
	)
	min_symptoms = 1
	max_symptoms = 3


// --- Slime dissolution (xenobio slimes, metroids) -----------------------------------------
// A feeding slime's digestive secretions break cells down to absorb them.
// Lasting cellular damage that does not heal by itself.
/datum/affliction/venom/slime_dissolution
	name = "cellular dissolution"
	category = "Genetic"
	subcategory = "Feeding injury"
	clinical_description = "Tissue partially digested by a feeding slime: cell membranes lysed, protein broken down and absorbed. Pallid, clammy skin and profound weakness. Does not resolve on its own; requires genetic repair (cryoxadone/clonexadone) and antitoxin for the absorbed byproducts."
	injury_category = INJURY_CATEGORY_GENETIC
	progression_rate = 0
	// A feeding slime digests a creature steadily while it latches.
	simple_load_rate = 3
	treated_by = list(TREAT_GENETIC_REPAIR = 1.5, TREAT_ANTITOXIN = 0.5)
	consciousness_at_max = 60
	pain_at_max = 40
	symptom_pool = list(
		/datum/affliction_symptom/pallor              = 90,
		/datum/affliction_symptom/fatigue             = 80,
		/datum/affliction_symptom/cold_mottled_skin   = 50,
		/datum/affliction_symptom/genetic_instability = 30,
	)
	min_symptoms = 1
	max_symptoms = 3

