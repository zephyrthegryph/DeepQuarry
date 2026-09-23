// Toxicology: named poisonings caused by specific reagents.
//
// A reagent that deserves its own clinical picture passes one of these as
// `affliction =` to injure() (toxin reagents set `poison_affliction`; see
// code/modules/reagents/reagents/toxins.dm). The patient then presents "phoron
// poisoning" rather than a generic toxic load, and the medic treats it by
// mechanism. All are systemic (INJURY_TOXIN, zone = null), organic-only, and
// count toward the toxic injury category like generic toxic poisoning.
//
// None of these self-resolve (progression_rate 0, like toxic_poisoning): the
// poison has to be cleared. Where a poison targets an organ it does so through
// organ_damage_* past a severity threshold, so untreated poisonings get worse.

/datum/affliction/poisoning
	name = "poisoning"
	category = "Toxic"
	subcategory = "Poisoning"
	injury_category = INJURY_CATEGORY_TOXIC
	biology = BIOLOGY_ORGANIC
	// Poisons act on any organic creature; on a simple body they keep
	// dealing toxin load until treated.
	body_plans = BODY_PLAN_ALL
	simple_load_rate = 1.5
	progression_rate = 0
	treated_by = list(TREAT_ANTITOXIN = 1.2)
	min_symptoms = 1
	max_symptoms = 3


// --- Phoron poisoning (liquid phoron, hydrophoron) ------------------------------------
/datum/affliction/poisoning/phoron
	name = "phoron poisoning"
	clinical_description = "Phoron absorbed into the bloodstream. A heavy, fast-acting systemic toxin: nausea, pallor, laboured breathing and mental dulling. Clear it with antitoxin; carthatoline for heavy exposures."
	treated_by = list(TREAT_ANTITOXIN = 1.0, TREAT_HEPATORENAL = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/nausea            = 85,
		/datum/affliction_symptom/pallor            = 70,
		/datum/affliction_symptom/labored_breathing = 50,
		/datum/affliction_symptom/dizziness         = 50,
		/datum/affliction_symptom/confusion         = 30,
	)


// --- Neurotoxin poisoning (carpotoxin, neurotoxic proteins) ------------------------------
/datum/affliction/poisoning/neurotoxin
	name = "neurotoxin poisoning"
	clinical_description = "A marine-type neurotoxin (space carp and kin) blocking nerve conduction: numb, tingling limbs, tremor, an unsteady gait and clouded thinking. Heavy doses dull consciousness. Antitoxin clears it; neural repair speeds recovery."
	treated_by = list(TREAT_ANTITOXIN = 1.2, TREAT_NEURAL_REPAIR = 0.3)
	consciousness_at_max = 50
	symptom_pool = list(
		/datum/affliction_symptom/numbness_arm  = 70,
		/datum/affliction_symptom/numbness_leg  = 70,
		/datum/affliction_symptom/jittery       = 50,
		/datum/affliction_symptom/unsteady_gait = 50,
		/datum/affliction_symptom/confusion     = 40,
	)


// --- Amatoxin poisoning (death-cap mushrooms) ------------------------------------------------
// The hepatotoxin: quiet at first, then the liver starts to fail.
/datum/affliction/poisoning/amatoxin
	name = "amatoxin poisoning"
	clinical_description = "Mushroom hepatotoxin. Deceptively mild at first — nausea and abdominal pain — before jaundice sets in as the liver is destroyed. Antitoxin with liver support; do not wait for symptoms to worsen."
	treated_by = list(TREAT_ANTITOXIN = 0.8, TREAT_HEPATORENAL = 0.8)
	symptom_pool = list(
		/datum/affliction_symptom/nausea               = 80,
		/datum/affliction_symptom/abdominal_tenderness = 70,
		/datum/affliction_symptom/jaundice             = 60,
		/datum/affliction_symptom/fatigue              = 50,
	)
	organ_damage_threshold = 40
	organ_damage_type = "internal"
	organ_damage_per_tick = 1
	organ_damage_targets = list(O_LIVER)


// --- Cyanide poisoning --------------------------------------------------------------------------
// Blocks cellular respiration: the blood is oxygenated but the tissues can't
// use it, so consciousness fails early.
/datum/affliction/poisoning/cyanide
	name = "cyanide poisoning"
	clinical_description = "Cellular respiration blocked by cyanide: the tissues suffocate despite adequate breathing. Headache, confusion, gasping, then collapse. Antitoxin clears the poison; oxygenation buys time."
	treated_by = list(TREAT_ANTITOXIN = 1.0, TREAT_OXYGENATION = 0.6)
	consciousness_at_max = 120
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 80,
		/datum/affliction_symptom/headache          = 60,
		/datum/affliction_symptom/confusion         = 60,
		/datum/affliction_symptom/drowsy            = 50,
	)


// --- Heavy-metal poisoning (lead, mercury) ---------------------------------------------------------
// Slow, cumulative, neurotoxic at high levels.
/datum/affliction/poisoning/heavy_metal
	name = "heavy-metal poisoning"
	clinical_description = "Lead or mercury accumulating in the tissues. Headaches, fatigue, tremor and abdominal pain; at high levels it damages the brain. Chelation with antitoxin is slow — keep dosing."
	treated_by = list(TREAT_ANTITOXIN = 0.6)
	symptom_pool = list(
		/datum/affliction_symptom/headache             = 70,
		/datum/affliction_symptom/fatigue              = 60,
		/datum/affliction_symptom/jittery              = 50,
		/datum/affliction_symptom/abdominal_tenderness = 40,
	)
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.5
	organ_damage_targets = list(O_BRAIN)


// --- Arachnid envenomation (giant spider toxins) ----------------------------------------------------
// A liquefying venom injected by giant spiders: painful and systemic.
/datum/affliction/venom/arachnid
	name = "arachnid envenomation"
	clinical_description = "Giant-spider venom beginning to liquefy tissue around the bite and spreading systemically. Burning pain, weakness, nausea. Antitoxin neutralises the venom; analgesics control the pain."
	progression_rate = 0
	pain_at_max = 60
	treated_by = list(TREAT_ANTITOXIN = 1.3, TREAT_ANALGESIC = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/sharp_pain     = 80,
		/datum/affliction_symptom/throbbing_pain = 60,
		/datum/affliction_symptom/limb_weakness  = 50,
		/datum/affliction_symptom/nausea         = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
