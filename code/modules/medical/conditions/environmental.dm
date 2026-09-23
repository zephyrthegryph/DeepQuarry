// Environmental / systemic conditions that aren't tied to a single
// injury or organ. Radiation and temperature are driven off a mob-level
// scalar via /datum/affliction_trigger/metric (see causes); toxin,
// hypoxia and genetic damage are the old damage pools themselves.

// --- Acute radiation sickness -------------------------------------------
//
// One staged condition. Stage chosen by the metric dispatcher reading
// the `radiation` value against per-outcome thresholds in the
// /datum/affliction_trigger/metric/acute_radiation cause. Symptoms
// fully swap when stage changes (no carryover).

/datum/affliction/acute_radiation
	name = "acute radiation sickness"
	category = "Radiation"
	clinical_description = "Symptoms of high-dose radiation exposure. Mild doses cause nausea and fatigue; severe doses produce spontaneous bleeding as the body's blood-forming tissues fail."
	progression_rate = 0
	// Arithrazine is the strong anti-rad drug but harsh on the body;
	// hyronalin is gentler but slower. Authoring the strong one first
	// makes the encyclopedia surface it as the primary treatment.
	treated_by = list(TREAT_ANTIRADIATION = 1.2)

/datum/affliction/acute_radiation/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"description" = "Early symptoms of radiation exposure — nausea and fatigue from a low-grade dose.",
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea             = 80,
				/datum/affliction_symptom/fatigue            = 80,
				/datum/affliction_symptom/headache           = 50,
				/datum/affliction_symptom/radiation_reading  = 95,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 3,
		),
		"Moderate" = list(
			"description" = "Moderate radiation exposure — repeated vomiting, hair loss, and visible bruising as bone marrow function falters.",
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea             = 95,
				/datum/affliction_symptom/fatigue            = 90,
				/datum/affliction_symptom/pallor             = 70,
				/datum/affliction_symptom/headache           = 60,
				/datum/affliction_symptom/dizziness          = 50,
				/datum/affliction_symptom/skin_burns_minor   = 60,
				/datum/affliction_symptom/radiation_reading  = 95,
			),
			"min_symptoms" = 3,
			"max_symptoms" = 5,
		),
		"Severe" = list(
			"description" = "Severe radiation exposure — multi-system failure approaches. Bone marrow function has effectively stopped; spontaneous bleeding follows.",
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea             = 95,
				/datum/affliction_symptom/fatigue            = 95,
				/datum/affliction_symptom/pallor             = 90,
				/datum/affliction_symptom/bleeding_visible   = 70,
				/datum/affliction_symptom/confusion          = 60,
				/datum/affliction_symptom/dizziness          = 60,
				/datum/affliction_symptom/skin_burns_minor   = 80,
				/datum/affliction_symptom/radiation_reading  = 95,
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

/datum/affliction/chronic_radiation
	name = "chronic radiation accumulation"
	category = "Radiation"
	clinical_description = "Accumulated radiation dose from sustained exposure. Slow to clear and subtle in presentation — vague fatigue, mild GI complaints."
	progression_rate = 0
	// Chronic dose responds to the gentler chems; arithrazine is too
	// harsh for slow steady clearance. Rezadone repairs cellular damage
	// at the genomic level.
	treated_by = list(TREAT_ANTIRADIATION = 1.6, TREAT_GENETIC_REPAIR = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/fatigue            = 80,
		/datum/affliction_symptom/nausea             = 50,
		/datum/affliction_symptom/headache           = 40,
		/datum/affliction_symptom/radiation_reading  = 80,
	)
	min_symptoms = 2
	max_symptoms = 3


// --- Toxic poisoning ---------------------------------------------------
//
// The toxin pool: every INJURY_TOXIN on a humanoid lands here as
// severity (body/plans/humanoid.dm). Covers phoron inhalation, ingested poison,
// snake bite, and the byproducts of liver failure. The liver is the
// natural host since it's the organ that processes toxins.

/datum/affliction/toxic_poisoning
	name = "toxic poisoning"
	category = "Toxic"
	clinical_description = "Toxins in the bloodstream exceed what the liver can clear. The patient looks sick — jaundiced, nauseous, lethargic."
	progression_rate = 0
	// Mild poisoning: antitoxin (dylovene) is enough. For severe cases
	// (high severity), carthatoline is the strong evacuant; necroxadone
	// addresses toxin-induced shock at the worst stages.
	treated_by = list(TREAT_ANTITOXIN = 1.4)
	symptom_pool = list(
		/datum/affliction_symptom/nausea       = 90,
		/datum/affliction_symptom/fatigue      = 80,
		/datum/affliction_symptom/jaundice     = 70,
		/datum/affliction_symptom/confusion    = 40,
		/datum/affliction_symptom/dizziness    = 40,
	)
	min_symptoms = 2
	max_symptoms = 4


// --- Tissue hypoxia ----------------------------------------------------
//
// The oxygen debt made visible: the physiology (body/physiology.dm) sets
// its severity from the debt. At severity 50 (consciousness_at_max) the
// patient passes out; past DQ_HYPOXIA_BRAIN_DAMAGE the brain starts dying.
// Distinct from acute respiratory_failure (a lung-failure condition): this is
// the systemic consequence of any shortfall in oxygen delivery, whether the
// airway, the lungs, the air, the blood, the heart or a poison is to blame.

/datum/affliction/tissue_hypoxia
	name = "tissue hypoxia"
	category = "Respiratory"
	clinical_description = "Oxygen demand exceeds delivery at the tissue level. Patients turn pale and dusky, breathing labored, mental status dulled. Resolved by treating the underlying cause and oxygenating."
	progression_rate = 0
	// Dexalin / dexalin-plus are the direct oxygenation chems. The lower
	// authored rates reflect that they only buy time while the underlying
	// driver (rad damage, OD, lung failure) is addressed.
	treated_by = list(TREAT_OXYGENATION = 1.0)
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 85,
		/datum/affliction_symptom/cyanosis          = 70,
		/datum/affliction_symptom/confusion         = 50,
		/datum/affliction_symptom/pallor            = 60,
		/datum/affliction_symptom/fatigue           = 60,
	)
	min_symptoms = 2
	max_symptoms = 4


// --- Hypothermia -------------------------------------------------------

/datum/affliction/hypothermia
	name = "hypothermia"
	category = "Environmental"
	clinical_description = "Core body temperature has dropped well below normal. Shivering, slowed movement, confusion."
	progression_rate = 0
	// Leporazine stabilises body temperature directly — the targeted
	// fix. Dermaline supports the cold-damaged skin while the core
	// rewarms.
	treated_by = list(TREAT_THERMOREGULATION = 1.4, TREAT_BURN_CARE = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/chills         = 95,
		/datum/affliction_symptom/pallor         = 70,
		/datum/affliction_symptom/confusion      = 50,
		/datum/affliction_symptom/fatigue        = 60,
		/datum/affliction_symptom/dizziness      = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 0.8, BF_ACCURACY = -10)
	spontaneous_emotes = list("shiver", "stamp their feet")
	spontaneous_emote_prob = 5


// --- Heatstroke --------------------------------------------------------

/datum/affliction/heatstroke
	name = "heatstroke"
	category = "Environmental"
	clinical_description = "Core body temperature has risen well above normal. Flushed skin, confusion, and weakness."
	progression_rate = 0
	// Leporazine handles core temperature; kelotane addresses the
	// sun/heat burns. Same chem family as cold exposure.
	treated_by = list(TREAT_THERMOREGULATION = 1.4, TREAT_BURN_CARE = 0.4)
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 95,
		/datum/affliction_symptom/pallor          = 50,
		/datum/affliction_symptom/confusion       = 50,
		/datum/affliction_symptom/dizziness       = 60,
		/datum/affliction_symptom/short_breath    = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 0.6, BF_ACCURACY = -8)
	spontaneous_emotes = list("wipe their brow", "pant")
	spontaneous_emote_prob = 4


// --- Genetic damage ----------------------------------------------------
//
// The genetic pool: every INJURY_CELLULAR on a humanoid lands here as
// severity (body/plans/humanoid.dm).

/datum/affliction/genetic_damage
	name = "genetic damage"
	category = "Genetic"
	clinical_description = "Damage at the cellular level — DNA strands disrupted by radiation, cloning errors, or other catalytic insult. Outwardly subtle; treated with ryetalyn."
	progression_rate = 0
	// Rezadone is the strong cellular-repair chem; ryetalyn is the
	// older genetic-only fix and still works but more slowly.
	treated_by = list(TREAT_GENETIC_REPAIR = 1.2)
	symptom_pool = list(
		/datum/affliction_symptom/fatigue              = 60,
		/datum/affliction_symptom/nausea               = 30,
		/datum/affliction_symptom/headache             = 30,
		/datum/affliction_symptom/genetic_instability  = 90,
	)
	min_symptoms = 1
	max_symptoms = 2
