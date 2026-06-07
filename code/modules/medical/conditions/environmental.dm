// Environmental / systemic conditions that aren't tied to a single
// injury or organ. Each is a damage-emergent condition driven off a
// mob-level scalar via /datum/dq_cause/metric_threshold (see causes).

// --- Acute radiation sickness -------------------------------------------
//
// One staged condition. Stage chosen by the metric dispatcher reading
// the `radiation` value against per-outcome thresholds in the
// /datum/dq_cause/metric_threshold/acute_radiation cause. Symptoms
// fully swap when stage changes (no carryover).

/datum/medical_issue/condition/acute_radiation
	name = "acute radiation sickness"
	category = "Radiation"
	clinical_description = "Symptoms of high-dose radiation exposure. Mild doses cause nausea and fatigue; severe doses produce spontaneous bleeding as the body's blood-forming tissues fail."
	progression_rate = 0
	// Arithrazine is the strong anti-rad drug but harsh on the body;
	// hyronalin is gentler but slower. Authoring the strong one first
	// makes the encyclopedia surface it as the primary treatment.
	cured_by = list(REAGENT_ID_ARITHRAZINE = 1.2, REAGENT_ID_HYRONALIN = 0.6)

/datum/medical_issue/condition/acute_radiation/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"description" = "Early symptoms of radiation exposure — nausea and fatigue from a low-grade dose.",
			"symptom_pool" = list(
				/datum/medical_symptom/nausea             = 80,
				/datum/medical_symptom/fatigue            = 80,
				/datum/medical_symptom/headache           = 50,
				/datum/medical_symptom/radiation_reading  = 95,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 3,
		),
		"Moderate" = list(
			"description" = "Moderate radiation exposure — repeated vomiting, hair loss, and visible bruising as bone marrow function falters.",
			"symptom_pool" = list(
				/datum/medical_symptom/nausea             = 95,
				/datum/medical_symptom/fatigue            = 90,
				/datum/medical_symptom/pallor             = 70,
				/datum/medical_symptom/headache           = 60,
				/datum/medical_symptom/dizziness          = 50,
				/datum/medical_symptom/skin_burns_minor   = 60,
				/datum/medical_symptom/radiation_reading  = 95,
			),
			"min_symptoms" = 3,
			"max_symptoms" = 5,
		),
		"Severe" = list(
			"description" = "Severe radiation exposure — multi-system failure approaches. Bone marrow function has effectively stopped; spontaneous bleeding follows.",
			"symptom_pool" = list(
				/datum/medical_symptom/nausea             = 95,
				/datum/medical_symptom/fatigue            = 95,
				/datum/medical_symptom/pallor             = 90,
				/datum/medical_symptom/bleeding_visible   = 70,
				/datum/medical_symptom/confusion          = 60,
				/datum/medical_symptom/dizziness          = 60,
				/datum/medical_symptom/skin_burns_minor   = 80,
				/datum/medical_symptom/radiation_reading  = 95,
			),
			"min_symptoms" = 4,
			"max_symptoms" = 6,
		),
	)
	return S


// --- Chronic radiation accumulation ------------------------------------
//
// Long-term cumulative dose (upstream `accumulated_rads`). Less acute
// but lingers after the acute exposure clears. Loss of taste, fatigue.

/datum/medical_issue/condition/chronic_radiation
	name = "chronic radiation accumulation"
	category = "Radiation"
	clinical_description = "Accumulated radiation dose from sustained exposure. Slow to clear and subtle in presentation — vague fatigue, mild GI complaints."
	progression_rate = 0
	// Chronic dose responds to the gentler chems; arithrazine is too
	// harsh for slow steady clearance. Rezadone repairs cellular damage
	// at the genomic level.
	cured_by = list(REAGENT_ID_HYRONALIN = 0.8, REAGENT_ID_REZADONE = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/fatigue            = 80,
		/datum/medical_symptom/nausea             = 50,
		/datum/medical_symptom/headache           = 40,
		/datum/medical_symptom/radiation_reading  = 80,
	)
	min_symptoms = 2
	max_symptoms = 3


// --- Toxic poisoning ---------------------------------------------------
//
// Single emergent condition driven by sustained toxloss. Covers phoron
// inhalation, ingested poison, snake bite, and the byproducts of liver
// failure. The liver is the natural host since it's the organ that
// processes toxins.

/datum/medical_issue/condition/toxic_poisoning
	name = "toxic poisoning"
	category = "Toxic"
	clinical_description = "Toxins in the bloodstream exceed what the liver can clear. The patient looks sick — jaundiced, nauseous, lethargic."
	progression_rate = 0
	// Mild poisoning: antitoxin (dylovene) is enough. For severe cases
	// (high severity), carthatoline is the strong evacuant; necroxadone
	// addresses toxin-induced shock at the worst stages.
	cured_by = list(
		REAGENT_ID_ANTITOXIN    = 0.8,
		REAGENT_ID_CARTHATOLINE = 1.4,
		REAGENT_ID_NECROXADONE  = 0.6,
	)
	symptom_pool = list(
		/datum/medical_symptom/nausea       = 90,
		/datum/medical_symptom/fatigue      = 80,
		/datum/medical_symptom/jaundice     = 70,
		/datum/medical_symptom/confusion    = 40,
		/datum/medical_symptom/dizziness    = 40,
	)
	min_symptoms = 2
	max_symptoms = 4


// --- Tissue hypoxia ----------------------------------------------------
//
// Single emergent condition driven by sustained mob-wide oxyloss. Covers
// the slow systemic insult of an unresolved oxygen debt — the patient
// is breathing but tissues aren't getting enough oxygen to function.
// Distinct from acute respiratory_failure (which is a lung-failure
// condition); this is the systemic consequence of any oxy-raising
// mechanism, including chem ODs that compromise oxygenation.

/datum/medical_issue/condition/tissue_hypoxia
	name = "tissue hypoxia"
	category = "Respiratory"
	clinical_description = "Oxygen demand exceeds delivery at the tissue level. Patients turn pale and dusky, breathing labored, mental status dulled. Resolved by treating the underlying cause and oxygenating."
	progression_rate = 0
	// Dexalin / dexalin-plus are the direct oxygenation chems. The lower
	// authored rates reflect that they only buy time while the underlying
	// driver (rad damage, OD, lung failure) is addressed.
	cured_by = list(REAGENT_ID_DEXALINP = 1.0, REAGENT_ID_DEXALIN = 0.5)
	symptom_pool = list(
		/datum/medical_symptom/labored_breathing = 85,
		/datum/medical_symptom/cyanosis          = 70,
		/datum/medical_symptom/confusion         = 50,
		/datum/medical_symptom/pallor            = 60,
		/datum/medical_symptom/fatigue           = 60,
	)
	min_symptoms = 2
	max_symptoms = 4


// --- Hypothermia -------------------------------------------------------

/datum/medical_issue/condition/hypothermia
	name = "hypothermia"
	category = "Environmental"
	clinical_description = "Core body temperature has dropped well below normal. Shivering, slowed movement, confusion."
	progression_rate = 0
	// Leporazine stabilises body temperature directly — the targeted
	// fix. Dermaline supports the cold-damaged skin while the core
	// rewarms.
	cured_by = list(REAGENT_ID_LEPORAZINE = 1.4, REAGENT_ID_DERMALINE = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/chills         = 95,
		/datum/medical_symptom/pallor         = 70,
		/datum/medical_symptom/confusion      = 50,
		/datum/medical_symptom/fatigue        = 60,
		/datum/medical_symptom/dizziness      = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	mechanical_effects = list(
		"slowdown" = 0.8,
		"accuracy_penalty" = 10,
		"spontaneous_emotes" = list("shiver", "stamp their feet"),
		"spontaneous_emote_prob" = 5,
	)


// --- Heatstroke --------------------------------------------------------

/datum/medical_issue/condition/heatstroke
	name = "heatstroke"
	category = "Environmental"
	clinical_description = "Core body temperature has risen well above normal. Flushed skin, confusion, and weakness."
	progression_rate = 0
	// Leporazine handles core temperature; kelotane addresses the
	// sun/heat burns. Same chem family as cold exposure.
	cured_by = list(REAGENT_ID_LEPORAZINE = 1.4, REAGENT_ID_KELOTANE = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/fever_sensation = 95,
		/datum/medical_symptom/pallor          = 50,
		/datum/medical_symptom/confusion       = 50,
		/datum/medical_symptom/dizziness       = 60,
		/datum/medical_symptom/short_breath    = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	mechanical_effects = list(
		"slowdown" = 0.6,
		"accuracy_penalty" = 8,
		"spontaneous_emotes" = list("wipe their brow", "pant"),
		"spontaneous_emote_prob" = 4,
	)


// --- Genetic damage ----------------------------------------------------

/datum/medical_issue/condition/genetic_damage
	name = "genetic damage"
	category = "Genetic"
	clinical_description = "Damage at the cellular level — DNA strands disrupted by radiation, cloning errors, or other catalytic insult. Outwardly subtle; treated with ryetalyn."
	progression_rate = 0
	// Rezadone is the strong cellular-repair chem; ryetalyn is the
	// older genetic-only fix and still works but more slowly.
	cured_by = list(REAGENT_ID_REZADONE = 1.2, REAGENT_ID_RYETALYN = 0.6)
	symptom_pool = list(
		/datum/medical_symptom/fatigue              = 60,
		/datum/medical_symptom/nausea               = 30,
		/datum/medical_symptom/headache             = 30,
		/datum/medical_symptom/genetic_instability  = 90,
	)
	min_symptoms = 1
	max_symptoms = 2
