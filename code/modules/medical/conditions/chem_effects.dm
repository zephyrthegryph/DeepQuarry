// Chem side effects and drug interactions.
//
// These conditions are spawned by the chem dispatcher (dq_check_chem_conditions
// in emergent.dm) while the relevant reagent(s) are in the body above a
// threshold. They despawn automatically when the chems clear — the
// patient doesn't have to do anything special to recover, the side
// effect just fades.
//
// All four kinds of effect are intentionally low-impact: mild symptoms
// that complicate the diagnostic picture rather than threaten the
// patient. A medic who sees "confusion" on a brain-damage patient who's
// been dosed with alkysine has to figure out whether the confusion is
// the brain damage (worsening) or the alkysine (expected side effect).
//
// Each condition declares its trigger via `caused_by_chems`:
//   list(REAGENT_ID = threshold) — single chem: side effect
//   list(A = threshold, B = threshold) — multi-chem: interaction
//
// `caused_by_chems_organ` sets the host organ for the spawned condition.
//
// All conditions live in `category = "Pharmacological"`. Progression
// rate is small/negative so they self-resolve when the chem clears.

// --- Single-chem side effects ------------------------------------------

/datum/affliction/alkysine_confusion
	name = "alkysine confusion"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Alkysine in the bloodstream at therapeutic dose can produce mild confusion. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves  // self-clears quickly once the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 70,
	)
	min_symptoms = 1
	max_symptoms = 1
	caused_by_chems = list(REAGENT_ID_ALKYSINE = 5)
	caused_by_chems_organ = O_BRAIN


/datum/affliction/antitoxin_nausea
	name = "antitoxin nausea"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Antitoxin scrubs toxins from the blood but the breakdown byproducts can churn the stomach. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/nausea = 80,
	)
	min_symptoms = 1
	max_symptoms = 1
	caused_by_chems = list(REAGENT_ID_ANTITOXIN = 10)
	caused_by_chems_organ = O_LIVER


/datum/affliction/oxycodone_drowsy
	name = "opioid drowsiness"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Oxycodone's analgesic effect comes paired with CNS depression. Patients on therapeutic-dose opioid are slower, drowsy, and at risk of respiratory suppression. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/drowsy           = 90,
		/datum/affliction_symptom/short_breath     = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	factors = alist(BF_SLOWDOWN = 0.4, BF_MOTOR_CONTROL = 0.98)
	spontaneous_emotes = list("yawn", "nod off")
	spontaneous_emote_prob = 4
	caused_by_chems = list(REAGENT_ID_OXYCODONE = 5)
	caused_by_chems_organ = O_BRAIN


/datum/affliction/tramadol_nausea
	name = "tramadol nausea"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Tramadol is a common analgesic but its action on serotonin receptors causes mild nausea and dizziness in many patients. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/dizziness = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_TRAMADOL = 8)
	caused_by_chems_organ = O_LIVER


/datum/affliction/synaptizine_jitter
	name = "synaptizine jitteriness"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Synaptizine's neuro-stimulant component can produce restless movements and elevated heart rate at therapeutic dose. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/jittery       = 80,
		/datum/affliction_symptom/palpitations  = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_SYNAPTIZINE = 5)
	caused_by_chems_organ = O_BRAIN


/datum/affliction/carthatoline_evacuant
	name = "carthatoline evacuation"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Carthatoline is a powerful gastrointestinal evacuant — it scrubs toxins out of the gut by force. The patient feels profoundly sick while it's working. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 95,
		/datum/affliction_symptom/pallor    = 60,
		/datum/affliction_symptom/fatigue   = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_CARTHATOLINE = 5)
	caused_by_chems_organ = O_LIVER


/datum/affliction/hyperzine_palpitations
	factors = alist(BF_HEART_RATE = 20, BF_BP_SYSTOLIC = 8)
	name = "stimulant tachycardia"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Hyperzine is a potent stimulant. Sub-overdose levels accelerate the heart and raise blood pressure in a noticeable way. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/palpitations = 90,
		/datum/affliction_symptom/jittery      = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_HYPERZINE = 5)
	caused_by_chems_organ = O_HEART

/datum/affliction/arithrazine_toxicity
	name = "arithrazine toxicity"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Arithrazine clears acute radiation aggressively but is harsh on the body's own tissues. Sustained high-dose use produces toxin damage. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/fatigue   = 60,
		/datum/affliction_symptom/jaundice  = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	// Stacks toxin injury while present — the chem really is harming the
	// patient even as it clears radiation.
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 0.6
	caused_by_chems = list(REAGENT_ID_ARITHRAZINE = 10)
	caused_by_chems_organ = O_LIVER


/datum/affliction/dexalinp_dysphoria
	name = "dexalin-plus dysphoria"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Dexalin-plus carries an oxygenation-related stimulant rush. Some patients report mild confusion and dissociative effects while on therapeutic dose. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 70,
		/datum/affliction_symptom/dizziness = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_DEXALINP = 5)
	caused_by_chems_organ = O_BRAIN


/datum/affliction/corophizine_gi
	name = "corophizine GI upset"
	category = "Pharmacological"
	subcategory = "Side effect"
	clinical_description = "Corophizine is wide-spectrum and effective but its disruption of normal gut flora causes significant GI symptoms during treatment. Resolves as the chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/nausea  = 80,
		/datum/affliction_symptom/fatigue = 50,
		/datum/affliction_symptom/pallor  = 30,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_COROPHIZINE = 5)
	caused_by_chems_organ = O_LIVER


// --- Drug interactions -------------------------------------------------

/datum/affliction/tachycardia_chem
	factors = alist(BF_HEART_RATE = 30)
	name = "drug-induced tachycardia"
	category = "Pharmacological"
	subcategory = "Interaction"
	clinical_description = "Inaprovaline (depressant) and hyperzine (stimulant) given together produce erratic, fast heart rate. Resolves when either chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/palpitations = 90,
		/datum/affliction_symptom/short_breath = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(
		REAGENT_ID_INAPROVALINE = 2,
		REAGENT_ID_HYPERZINE    = 2,
	)
	caused_by_chems_organ = O_HEART

// Bicaridine + spaceacillin: silent marker that reduces spaceacillin's
// cure rate on OTHER conditions via interferes_with. The encyclopedia
// still lists it so a medic can learn why their antibiotics aren't
// working.
/datum/affliction/bicaridine_antibiotic_interference
	name = "antibiotic interference"
	category = "Pharmacological"
	subcategory = "Interaction"
	clinical_description = "Bicaridine's antiplatelet activity interferes with spaceacillin absorption. Spaceacillin treats infections at 40% of its normal effectiveness while both are in the body."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_SPACEACILLIN = 0.4)
	caused_by_chems = list(
		REAGENT_ID_BICARIDINE   = 2,
		REAGENT_ID_SPACEACILLIN = 2,
	)
	caused_by_chems_organ = O_LIVER


/datum/affliction/opioid_co_administration
	name = "compound CNS depression"
	category = "Pharmacological"
	subcategory = "Interaction"
	clinical_description = "Combining tramadol and oxycodone produces additive CNS depression — drowsiness, respiratory suppression, and slowed reflexes well beyond either alone. Resolves when either chem clears."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/drowsy            = 95,
		/datum/affliction_symptom/labored_breathing = 80,
		/datum/affliction_symptom/confusion         = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 1.5, BF_ACCURACY = -25, BF_MOTOR_CONTROL = 0.94, BF_O2_SAT = -8, BF_RESP_RATE = -6)
	spontaneous_emotes = list("yawn", "stumble", "nod off")
	spontaneous_emote_prob = 6
	caused_by_chems = list(
		REAGENT_ID_TRAMADOL  = 3,
		REAGENT_ID_OXYCODONE = 3,
	)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/antibiotic_cross_interference
	name = "antibiotic cross-interference"
	category = "Pharmacological"
	subcategory = "Interaction"
	clinical_description = "Spaceacillin and corophizine target similar bacterial mechanisms; given together they compete for absorption and both work at reduced effectiveness."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(
		REAGENT_ID_SPACEACILLIN = 0.5,
		REAGENT_ID_COROPHIZINE  = 0.5,
	)
	caused_by_chems = list(
		REAGENT_ID_SPACEACILLIN = 2,
		REAGENT_ID_COROPHIZINE  = 2,
	)
	caused_by_chems_organ = O_LIVER


/datum/affliction/peridaxon_daxon_synergy
	name = "potentiated organ repair"
	category = "Pharmacological"
	subcategory = "Interaction"
	clinical_description = "Peridaxon's generic organ-repair pathway primes tissue receptors so the targeted daxon-family drugs (cordradaxon, respirodaxon, hepanephrodaxon, gastirodaxon) work faster. A documented synergy."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	min_symptoms = 0
	max_symptoms = 0
	// Positive multiplier — the daxon drugs work 1.6× as fast while
	// peridaxon is also in the body. Realistic synergy modeled with
	// the same interferes_with channel as the negative interactions.
	interferes_with = list(
		REAGENT_ID_CORDRADAXON       = 1.6,
		REAGENT_ID_RESPIRODAXON      = 1.6,
		REAGENT_ID_HEPANEPHRODAXON   = 1.6,
		REAGENT_ID_GASTIRODAXON      = 1.6,
	)
	// Synergy fires when peridaxon + ANY one of the daxons is present.
	// caused_by_chems demands EVERY listed chem, so we'd need four
	// near-duplicate conditions. The dispatcher API doesn't yet support
	// "A AND any-of-{B,C,D,E}", so for now we model it as the simplest
	// reliable case — peridaxon + cordradaxon — which is the common
	// post-cardiac-arrest pairing. Future: extend the dispatcher API.
	caused_by_chems = list(
		REAGENT_ID_PERIDAXON   = 2,
		REAGENT_ID_CORDRADAXON = 2,
	)
	caused_by_chems_organ = O_LIVER


/datum/affliction/synaptizine_alkysine_potentiation
	name = "potentiated neurorepair"
	category = "Pharmacological"
	subcategory = "Interaction"
	clinical_description = "Synaptizine opens the blood-brain barrier slightly, letting alkysine reach more damaged neural tissue per dose. The chems work together better than apart."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_ALKYSINE = 1.5)
	caused_by_chems = list(
		REAGENT_ID_SYNAPTIZINE = 2,
		REAGENT_ID_ALKYSINE    = 2,
	)
	caused_by_chems_organ = O_BRAIN


/datum/affliction/cardiac_stress_interaction
	factors = alist(BF_HEART_RATE = 25, BF_BP_SYSTOLIC = 10)
	name = "cardiac stress"
	category = "Pharmacological"
	subcategory = "Interaction"
	clinical_description = "Stimulant-driven tachycardia compounds the load on a heart that's actively trying to repair itself. Hyperzine and cordradaxon together stress the cardiac muscle even as the latter tries to heal it."
	progression_rate = 0  // dispatcher clears as soon as the chem leaves
	symptom_pool = list(
		/datum/affliction_symptom/palpitations       = 90,
		/datum/affliction_symptom/sharp_chest_pain   = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	// Reduce cordradaxon's effectiveness AND damage the heart organ
	// while the combo holds. The interference handles the cure-rate
	// reduction; the organ_damage_* fields stack heart damage like
	// the heart_damage condition does.
	interferes_with = list(REAGENT_ID_CORDRADAXON = 0.6)
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.4
	organ_damage_targets = list(O_HEART)
	caused_by_chems = list(
		REAGENT_ID_HYPERZINE   = 3,
		REAGENT_ID_CORDRADAXON = 2,
	)
	caused_by_chems_organ = O_HEART

// --- Overdose conditions ----------------------------------------------
//
// Each medical reagent that has an `overdose` threshold in the upstream
// /datum/reagent declaration gets a matching condition here. The
// dispatcher spawns it when the reagent crosses the OD threshold,
// clears it as the chem metabolizes back down. Encyclopedia links from
// the reagent's Overdose section to these conditions directly.
//
// Thresholds match the upstream `overdose` values (look in
// code/modules/reagents/reagents/medicine.dm).

/datum/affliction/peridaxon_overdose
	name = "peridaxon overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Peridaxon at overdose induces hallucinations and disorientation — the same organ-receptor priming that makes it useful at therapeutic dose becomes overwhelming at high concentrations."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 85,
		/datum/affliction_symptom/jittery   = 60,
		/datum/affliction_symptom/headache  = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_PERIDAXON = 10)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/peridaxon_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery = 60,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion = 70,
				/datum/affliction_symptom/jittery   = 50,
				/datum/affliction_symptom/headache  = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion = 95,
				/datum/affliction_symptom/jittery   = 80,
				/datum/affliction_symptom/headache  = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
	)
	return S


/datum/affliction/hyperzine_overdose
	name = "stimulant overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Hyperzine at overdose drives the heart and adrenergic system past their working range. Severe tachycardia, hypertension, toxic muscle stress. Patients in this state move noticeably faster and shrug off pain — combat use is a known abuse, but the heart strain and toxin damage are real."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/palpitations     = 95,
		/datum/affliction_symptom/jittery          = 80,
		/datum/affliction_symptom/sharp_chest_pain = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 1.0
	factors = alist(BF_SLOWDOWN = -1, BF_ACCURACY = 20, BF_ANALGESIA = 15, BF_HEART_RATE = 40, BF_BP_SYSTOLIC = 20)
	caused_by_chems = list(REAGENT_ID_HYPERZINE = 20)
	caused_by_chems_organ = O_HEART

/datum/affliction/hyperzine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/palpitations = 70,
				/datum/affliction_symptom/jittery      = 60,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"organ_damage_per_tick" = 0.3,
			"factors" = alist(BF_SLOWDOWN = -0.4, BF_ACCURACY = 8, BF_ANALGESIA = 5, BF_HEART_RATE = 15, BF_BP_SYSTOLIC = 8),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/palpitations     = 90,
				/datum/affliction_symptom/jittery          = 80,
				/datum/affliction_symptom/sharp_chest_pain = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.7,
			"factors" = alist(BF_SLOWDOWN = -0.8, BF_ACCURACY = 15, BF_ANALGESIA = 10, BF_HEART_RATE = 28, BF_BP_SYSTOLIC = 14),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/palpitations     = 100,
				/datum/affliction_symptom/jittery          = 90,
				/datum/affliction_symptom/sharp_chest_pain = 80,
				/datum/affliction_symptom/chest_pain_crushing = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 1.4,
			"factors" = alist(BF_SLOWDOWN = -1.2, BF_ACCURACY = 25, BF_ANALGESIA = 20, BF_HEART_RATE = 45, BF_BP_SYSTOLIC = 25),
			"always_spawns" = list(/datum/affliction/heart_damage, /datum/affliction/tachycardia_chem),
		),
	)
	return S

/datum/affliction/bicaridine_overdose
	name = "bicaridine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Bicaridine at overdose interferes with normal clotting — the patient becomes prone to spontaneous bleeding. The same antiplatelet activity also drains intracranial bleeding faster than any other chem can; a bicaridine OD will resolve a subdural hematoma when no surgeon is available, at the cost of broad external bleeding."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/bleeding_visible = 80,
		/datum/affliction_symptom/pallor           = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	od_cures_externally = list(/datum/affliction/subdural_hematoma = 0.8)
	caused_by_chems = list(REAGENT_ID_BICARIDINE = 20)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/bicaridine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/pallor = 60,
			),
			"min_symptoms" = 0, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/bleeding_visible = 80,
				/datum/affliction_symptom/pallor           = 60,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/bleeding_visible = 100,
				/datum/affliction_symptom/pallor           = 80,
				/datum/affliction_symptom/dizziness        = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"always_spawns" = list(/datum/affliction/internal_hemorrhage),
		),
	)
	return S


/datum/affliction/bicaridaze_overdose
	name = "bicaridaze overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Bicaridaze is a topical bicaridine that's absorbed slowly through the skin. At overdose the same antiplatelet effect as bicaridine itself surfaces — bleeding becomes harder to control — with the added burden of cumulative skin/dermal irritation from the carrier."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/bleeding_visible  = 70,
		/datum/affliction_symptom/pallor            = 60,
		/datum/affliction_symptom/skin_burns_minor  = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_BICARIDAZE = 22)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/bicaridaze_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/pallor           = 50,
				/datum/affliction_symptom/skin_burns_minor = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/bleeding_visible  = 70,
				/datum/affliction_symptom/pallor            = 60,
				/datum/affliction_symptom/skin_burns_minor  = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/bleeding_visible  = 90,
				/datum/affliction_symptom/pallor            = 80,
				/datum/affliction_symptom/skin_burns_minor  = 70,
				/datum/affliction_symptom/dizziness         = 60,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
		),
	)
	return S


/datum/affliction/dexalin_overdose
	name = "dexalin overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Excess dexalin disrupts normal oxygen exchange — paradoxically, too much makes breathing less effective."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 80,
		/datum/affliction_symptom/confusion         = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_DEXALIN = 20)
	caused_by_chems_organ = O_LUNGS

/datum/affliction/dexalin_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/short_breath = 60,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/labored_breathing = 80,
				/datum/affliction_symptom/confusion         = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"factors" = alist(BF_O2_SAT = -8),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/labored_breathing = 95,
				/datum/affliction_symptom/cyanosis          = 70,
				/datum/affliction_symptom/confusion         = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"factors" = alist(BF_O2_SAT = -15, BF_RESP_RATE = -4),
			"always_spawns" = list(/datum/affliction/respiratory_failure),
		),
	)
	return S


/datum/affliction/dexalinp_overdose
	name = "dexalin-plus overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Dexalin-plus at overdose causes the same paradoxical oxygenation failure as dexalin, but at higher intensity, with confusion and motor symptoms."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 90,
		/datum/affliction_symptom/confusion         = 70,
		/datum/affliction_symptom/unsteady_gait     = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_DEXALINP = 20)
	caused_by_chems_organ = O_LUNGS

/datum/affliction/dexalinp_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/short_breath = 70,
				/datum/affliction_symptom/dizziness    = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/labored_breathing = 85,
				/datum/affliction_symptom/confusion         = 60,
				/datum/affliction_symptom/unsteady_gait     = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"factors" = alist(BF_O2_SAT = -10),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/labored_breathing = 100,
				/datum/affliction_symptom/cyanosis          = 80,
				/datum/affliction_symptom/confusion         = 80,
				/datum/affliction_symptom/unsteady_gait     = 70,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"factors" = alist(BF_O2_SAT = -20, BF_RESP_RATE = -5),
			"always_spawns" = list(/datum/affliction/respiratory_failure),
		),
	)
	return S


/datum/affliction/inaprovaline_overdose
	factors = alist(BF_HEART_RATE = -15, BF_BP_SYSTOLIC = -20)
	name = "inaprovaline overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Excess inaprovaline depresses cardiac output. Hypotension, bradycardia, and reduced respiratory drive."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/pallor        = 70,
		/datum/affliction_symptom/short_breath  = 60,
		/datum/affliction_symptom/drowsy        = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_INAPROVALINE = 60)
	caused_by_chems_organ = O_HEART

/datum/affliction/inaprovaline_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/drowsy = 60,
				/datum/affliction_symptom/pallor = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"factors" = alist(BF_HEART_RATE = -5, BF_BP_SYSTOLIC = -8),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/pallor       = 75,
				/datum/affliction_symptom/short_breath = 60,
				/datum/affliction_symptom/drowsy       = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"factors" = alist(BF_HEART_RATE = -12, BF_BP_SYSTOLIC = -15),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/pallor             = 90,
				/datum/affliction_symptom/labored_breathing  = 80,
				/datum/affliction_symptom/drowsy             = 80,
				/datum/affliction_symptom/cold_mottled_skin  = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"factors" = alist(BF_HEART_RATE = -22, BF_BP_SYSTOLIC = -28, BF_RESP_RATE = -3),
			"always_spawns" = list(/datum/affliction/hypovolemic_shock),
		),
	)
	return S

/datum/affliction/oxycodone_overdose
	name = "opioid overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Oxycodone at overdose causes profound CNS depression — the patient may stop breathing entirely. Pinpoint pupils, slow heart, shallow respirations. The same effect produces near-total pain immunity and significant stun resistance — sometimes worth the risk when working through a major procedure under fire."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/drowsy            = 95,
		/datum/affliction_symptom/labored_breathing = 85,
		/datum/affliction_symptom/cyanosis          = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 2, BF_ACCURACY = -40, BF_MOTOR_CONTROL = 0.9, BF_DISABLE_DURATION = 0.5, BF_ANALGESIA = 50, BF_HEART_RATE = -15, BF_O2_SAT = -20, BF_RESP_RATE = -10)
	spontaneous_emotes = list("collapse", "yawn", "fall")
	spontaneous_emote_prob = 10
	caused_by_chems = list(REAGENT_ID_OXYCODONE = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/oxycodone_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/drowsy       = 75,
				/datum/affliction_symptom/short_breath = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"factors" = alist(BF_SLOWDOWN = 0.6, BF_ACCURACY = -10, BF_DISABLE_DURATION = 0.85, BF_ANALGESIA = 20, BF_HEART_RATE = -5, BF_O2_SAT = -6, BF_RESP_RATE = -3),
			"spontaneous_emotes" = list("yawn"),
			"spontaneous_emote_prob" = 3,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/drowsy            = 90,
				/datum/affliction_symptom/labored_breathing = 80,
				/datum/affliction_symptom/dizziness         = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"factors" = alist(BF_SLOWDOWN = 1.4, BF_ACCURACY = -25, BF_MOTOR_CONTROL = 0.95, BF_DISABLE_DURATION = 0.7, BF_ANALGESIA = 37.5, BF_HEART_RATE = -10, BF_O2_SAT = -14, BF_RESP_RATE = -7),
			"spontaneous_emotes" = list("yawn", "nod off"),
			"spontaneous_emote_prob" = 6,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/drowsy            = 100,
				/datum/affliction_symptom/labored_breathing = 100,
				/datum/affliction_symptom/cyanosis          = 85,
				/datum/affliction_symptom/cold_mottled_skin = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"factors" = alist(BF_SLOWDOWN = 2.4, BF_ACCURACY = -50, BF_MOTOR_CONTROL = 0.88, BF_DISABLE_DURATION = 0.5, BF_ANALGESIA = 50, BF_HEART_RATE = -18, BF_O2_SAT = -25, BF_RESP_RATE = -12),
			"spontaneous_emotes" = list("collapse", "yawn", "fall"),
			"spontaneous_emote_prob" = 12,
			"always_spawns" = list(/datum/affliction/respiratory_arrest),
		),
	)
	return S

// Neuro chems
/datum/affliction/alkysine_overdose
	name = "alkysine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Excess alkysine is itself neurotoxic — the same neurotransmitter pathway it's meant to support gets overwhelmed. Confusion, headache, and accumulating brain damage."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 80,
		/datum/affliction_symptom/headache  = 60,
		/datum/affliction_symptom/jittery   = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.5
	organ_damage_targets = list(O_BRAIN)
	caused_by_chems = list(REAGENT_ID_ALKYSINE = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/alkysine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/headache = 60,
				/datum/affliction_symptom/jittery  = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
			"organ_damage_per_tick" = 0.15,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion = 75,
				/datum/affliction_symptom/headache  = 60,
				/datum/affliction_symptom/jittery   = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"organ_damage_per_tick" = 0.35,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion           = 95,
				/datum/affliction_symptom/headache            = 80,
				/datum/affliction_symptom/jittery             = 60,
				/datum/affliction_symptom/pupillary_asymmetry = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.7,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
		),
	)
	return S


/datum/affliction/synaptizine_overdose
	name = "synaptizine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Synaptizine at overdose drives the CNS past stimulation into excitotoxicity — restless tremor, accelerated heart rate, tissue stress on the brain. The chem also crosses the blood-brain barrier hard enough at OD doses to repair tissue damage above the salvage threshold — but only enough to win if paired with alkysine. Past the terminal threshold, brain decay outpaces any combination."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/jittery        = 90,
		/datum/affliction_symptom/palpitations   = 70,
		/datum/affliction_symptom/confusion      = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.4
	organ_damage_targets = list(O_BRAIN)
	factors = alist(BF_NEURAL_REPAIR = 0.3)
	caused_by_chems = list(REAGENT_ID_SYNAPTIZINE = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/synaptizine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery     = 70,
				/datum/affliction_symptom/palpitations = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"organ_damage_per_tick" = 0.15,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
			"factors" = alist(BF_NEURAL_REPAIR = 0.1),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery     = 85,
				/datum/affliction_symptom/palpitations = 70,
				/datum/affliction_symptom/confusion   = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.3,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
			"factors" = alist(BF_NEURAL_REPAIR = 0.22),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery        = 100,
				/datum/affliction_symptom/palpitations   = 85,
				/datum/affliction_symptom/confusion      = 70,
				/datum/affliction_symptom/sharp_chest_pain = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 0.5,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
			"factors" = alist(BF_NEURAL_REPAIR = 0.35),
			"always_spawns" = list(/datum/affliction/tachycardia_chem),
		),
	)
	return S


// Burn chems
/datum/affliction/kelotane_overdose
	name = "kelotane overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Excess kelotane irritates the digestive tract. Nausea and tissue inflammation as the drug overwhelms the body's normal burn-response pathway."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea  = 70,
		/datum/affliction_symptom/pallor  = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_KELOTANE = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/kelotane_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(/datum/affliction_symptom/nausea = 60),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea = 75,
				/datum/affliction_symptom/pallor = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea          = 90,
				/datum/affliction_symptom/pallor          = 75,
				/datum/affliction_symptom/skin_burns_minor = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
	)
	return S


/datum/affliction/dermaline_overdose
	name = "dermaline overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Dermaline's potency makes its overdose harsher than kelotane's. Severe nausea, vascular dilation, and broad tissue irritation."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea   = 80,
		/datum/affliction_symptom/pallor   = 60,
		/datum/affliction_symptom/dizziness = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_DERMALINE = 15)
	caused_by_chems_organ = O_LIVER

/datum/affliction/dermaline_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea = 65,
				/datum/affliction_symptom/pallor = 45,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea    = 80,
				/datum/affliction_symptom/pallor    = 65,
				/datum/affliction_symptom/dizziness = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea          = 95,
				/datum/affliction_symptom/pallor          = 85,
				/datum/affliction_symptom/dizziness       = 70,
				/datum/affliction_symptom/skin_burns_minor = 60,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
		),
	)
	return S


// Toxicology
/datum/affliction/antitoxin_overdose
	name = "antitoxin overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Antitoxin at overdose disrupts the body's normal electrolyte balance. Patients become weak, nauseated, and disoriented."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea     = 70,
		/datum/affliction_symptom/fatigue    = 80,
		/datum/affliction_symptom/confusion  = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_ANTITOXIN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/antitoxin_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea  = 60,
				/datum/affliction_symptom/fatigue = 60,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea     = 75,
				/datum/affliction_symptom/fatigue    = 80,
				/datum/affliction_symptom/confusion  = 40,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea     = 90,
				/datum/affliction_symptom/fatigue    = 95,
				/datum/affliction_symptom/confusion  = 65,
				/datum/affliction_symptom/limb_weakness = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"always_spawns" = list(/datum/affliction/toxic_poisoning),
		),
	)
	return S


/datum/affliction/carthatoline_overdose
	name = "carthatoline overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Carthatoline at overdose strips the patient's electrolytes alongside the toxins it's meant to clear. Dehydration, weakness, and ongoing GI distress."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea     = 95,
		/datum/affliction_symptom/pallor     = 80,
		/datum/affliction_symptom/fatigue    = 70,
		/datum/affliction_symptom/dizziness  = 50,
	)
	min_symptoms = 2
	max_symptoms = 4
	caused_by_chems = list(REAGENT_ID_CARTHATOLINE = 15)
	caused_by_chems_organ = O_LIVER

/datum/affliction/carthatoline_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea = 75,
				/datum/affliction_symptom/fatigue = 55,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea    = 90,
				/datum/affliction_symptom/pallor    = 75,
				/datum/affliction_symptom/fatigue   = 70,
				/datum/affliction_symptom/dizziness = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea     = 100,
				/datum/affliction_symptom/pallor     = 95,
				/datum/affliction_symptom/fatigue    = 90,
				/datum/affliction_symptom/dizziness  = 75,
				/datum/affliction_symptom/cold_mottled_skin = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
		),
	)
	return S


// Eye drug
/datum/affliction/imidazoline_overdose
	name = "imidazoline overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Imidazoline at overdose paradoxically blurs vision and irritates the retina — too much of the receptor agonist overwhelms the normal signal."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/blurred_vision = 80,
		/datum/affliction_symptom/cloudy_eye     = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_IMIDAZOLINE = 20)
	caused_by_chems_organ = O_EYES

/datum/affliction/imidazoline_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/blurred_vision = 55,
				/datum/affliction_symptom/cloudy_eye     = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/blurred_vision = 80,
				/datum/affliction_symptom/cloudy_eye     = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/blurred_vision      = 95,
				/datum/affliction_symptom/cloudy_eye          = 80,
				/datum/affliction_symptom/pupillary_asymmetry = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
	)
	return S


// Daxon family — generalised systemic stress
/datum/affliction/osteodaxon_overdose
	name = "osteodaxon overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Excess osteodaxon causes calcium dysregulation — muscle cramps, weakness, and bone pain visible as unsteadiness."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/throbbing_pain  = 70,
		/datum/affliction_symptom/fatigue         = 60,
		/datum/affliction_symptom/unsteady_gait   = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_OSTEODAXON = 15)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/osteodaxon_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/throbbing_pain = 55,
				/datum/affliction_symptom/fatigue        = 45,
				/datum/affliction_symptom/unsteady_gait  = 35,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/throbbing_pain = 75,
				/datum/affliction_symptom/fatigue        = 65,
				/datum/affliction_symptom/unsteady_gait  = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/throbbing_pain = 90,
				/datum/affliction_symptom/fatigue        = 85,
				/datum/affliction_symptom/unsteady_gait  = 75,
				/datum/affliction_symptom/limb_weakness  = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
	)
	return S


/datum/affliction/respirodaxon_overdose
	name = "respirodaxon overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Respirodaxon overdose over-proliferates lung tissue, paradoxically reducing gas exchange efficiency."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 80,
		/datum/affliction_symptom/wet_cough         = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_RESPIRODAXON = 10)
	caused_by_chems_organ = O_LUNGS

/datum/affliction/respirodaxon_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/wet_cough   = 60,
				/datum/affliction_symptom/short_breath = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/labored_breathing = 75,
				/datum/affliction_symptom/wet_cough         = 60,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"factors" = alist(BF_O2_SAT = -6),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/labored_breathing = 95,
				/datum/affliction_symptom/wet_cough         = 80,
				/datum/affliction_symptom/cyanosis          = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"factors" = alist(BF_O2_SAT = -14, BF_RESP_RATE = -4),
			"always_spawns" = list(/datum/affliction/respiratory_failure),
		),
	)
	return S


/datum/affliction/cordradaxon_overdose
	name = "cordradaxon overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Cordradaxon overdose drives over-proliferation of cardiac tissue receptors — palpitations, chest discomfort, irregular rhythm. At peak severity the same receptor flood pulls a patient out of cardiac arrest at speeds open surgery would envy; the arrhythmia is the price."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/palpitations     = 90,
		/datum/affliction_symptom/sharp_chest_pain = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	od_cures_externally = list(/datum/affliction/heart_damage = 1.2)
	caused_by_chems = list(REAGENT_ID_CORDRADAXON = 10)
	caused_by_chems_organ = O_HEART

/datum/affliction/cordradaxon_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(/datum/affliction_symptom/palpitations = 60),
			"min_symptoms" = 0, "max_symptoms" = 1,
			"factors" = alist(BF_HEART_RATE = 10),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/palpitations     = 85,
				/datum/affliction_symptom/sharp_chest_pain = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"factors" = alist(BF_HEART_RATE = 20),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/palpitations        = 100,
				/datum/affliction_symptom/sharp_chest_pain    = 80,
				/datum/affliction_symptom/chest_pain_crushing = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"factors" = alist(BF_HEART_RATE = 35),
			"always_spawns" = list(/datum/affliction/tachycardia_chem),
		),
	)
	return S


/datum/affliction/hepanephrodaxon_overdose
	name = "hepanephrodaxon overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Hepanephrodaxon overdose strains the very organs it normally repairs — the chem overwhelms hepatic/renal receptors and produces metabolic upset."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/fatigue   = 70,
		/datum/affliction_symptom/jaundice  = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_HEPANEPHRODAXON = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/hepanephrodaxon_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea  = 55,
				/datum/affliction_symptom/fatigue = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea   = 75,
				/datum/affliction_symptom/fatigue  = 70,
				/datum/affliction_symptom/jaundice = 40,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea               = 90,
				/datum/affliction_symptom/fatigue              = 90,
				/datum/affliction_symptom/jaundice             = 75,
				/datum/affliction_symptom/abdominal_tenderness = 55,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
		),
	)
	return S


/datum/affliction/gastirodaxon_overdose
	name = "gastirodaxon overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Gastirodaxon overdose causes inflammatory GI cramping and impaired absorption."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea           = 80,
		/datum/affliction_symptom/throbbing_pain   = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_GASTIRODAXON = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/gastirodaxon_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(/datum/affliction_symptom/nausea = 60),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea         = 80,
				/datum/affliction_symptom/throbbing_pain = 55,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea               = 95,
				/datum/affliction_symptom/throbbing_pain       = 80,
				/datum/affliction_symptom/abdominal_tenderness = 65,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
	)
	return S


// Cellular / genetic
/datum/affliction/rezadone_overdose
	name = "rezadone overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Rezadone at overdose causes uncontrolled cellular replication — disorientation, weakness, and minor toxic effects as the body struggles to keep up."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 60,
		/datum/affliction_symptom/fatigue   = 70,
		/datum/affliction_symptom/nausea    = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_REZADONE = 20)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/rezadone_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue = 55,
				/datum/affliction_symptom/nausea  = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion = 60,
				/datum/affliction_symptom/fatigue   = 70,
				/datum/affliction_symptom/nausea    = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion           = 80,
				/datum/affliction_symptom/fatigue             = 85,
				/datum/affliction_symptom/nausea              = 70,
				/datum/affliction_symptom/genetic_instability = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"always_spawns" = list(/datum/affliction/genetic_damage),
		),
	)
	return S


/datum/affliction/ryetalyn_overdose
	name = "ryetalyn overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Ryetalyn at overdose interferes with normal cellular processes outside the genetic targets it's meant to fix. Weakness and mild GI symptoms."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/fatigue = 70,
		/datum/affliction_symptom/nausea  = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_RYETALYN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/ryetalyn_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue = 55,
				/datum/affliction_symptom/nausea  = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue = 75,
				/datum/affliction_symptom/nausea  = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue             = 90,
				/datum/affliction_symptom/nausea              = 70,
				/datum/affliction_symptom/genetic_instability = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"always_spawns" = list(/datum/affliction/genetic_damage),
		),
	)
	return S


// Rad chems
/datum/affliction/hyronalin_overdose
	name = "hyronalin overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Hyronalin overdose stresses the same tissues it's meant to protect — patients feel weak and queasy."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/fatigue = 70,
		/datum/affliction_symptom/nausea  = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_HYRONALIN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/hyronalin_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue = 55,
				/datum/affliction_symptom/nausea  = 45,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue = 75,
				/datum/affliction_symptom/nausea  = 60,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue           = 90,
				/datum/affliction_symptom/nausea            = 80,
				/datum/affliction_symptom/radiation_reading = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"always_spawns" = list(/datum/affliction/acute_radiation),
		),
	)
	return S


// Environmental
/datum/affliction/leporazine_overdose
	name = "leporazine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Leporazine overdose causes thermoregulatory chaos — the patient's temperature swings unpredictably, accompanied by chills and sweats."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/chills            = 70,
		/datum/affliction_symptom/fever_sensation   = 60,
		/datum/affliction_symptom/fatigue           = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_LEPORAZINE = 20)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/leporazine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/chills          = 55,
				/datum/affliction_symptom/fever_sensation = 45,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/chills          = 75,
				/datum/affliction_symptom/fever_sensation = 65,
				/datum/affliction_symptom/fatigue         = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/chills            = 90,
				/datum/affliction_symptom/fever_sensation   = 85,
				/datum/affliction_symptom/fatigue           = 70,
				/datum/affliction_symptom/cold_mottled_skin = 55,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"always_spawns" = list(/datum/affliction/heatstroke, /datum/affliction/hypothermia),
		),
	)
	return S


// Antibiotics
/datum/affliction/spaceacillin_overdose
	name = "spaceacillin overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Spaceacillin overdose produces broad GI disturbance and mild liver stress."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea  = 70,
		/datum/affliction_symptom/fatigue = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_SPACEACILLIN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/spaceacillin_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(/datum/affliction_symptom/nausea = 55),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea  = 75,
				/datum/affliction_symptom/fatigue = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea   = 90,
				/datum/affliction_symptom/fatigue  = 75,
				/datum/affliction_symptom/jaundice = 55,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"always_spawns" = list(/datum/affliction/toxic_poisoning),
		),
	)
	return S


/datum/affliction/corophizine_overdose
	name = "corophizine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Corophizine at overdose is markedly more harsh than therapeutic dose — severe GI symptoms, liver irritation, and weakness."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 90,
		/datum/affliction_symptom/jaundice  = 50,
		/datum/affliction_symptom/fatigue   = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_COROPHIZINE = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/corophizine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea  = 70,
				/datum/affliction_symptom/fatigue = 45,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea   = 90,
				/datum/affliction_symptom/jaundice = 50,
				/datum/affliction_symptom/fatigue  = 60,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea               = 100,
				/datum/affliction_symptom/jaundice             = 75,
				/datum/affliction_symptom/fatigue              = 80,
				/datum/affliction_symptom/abdominal_tenderness = 55,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"always_spawns" = list(/datum/affliction/toxic_poisoning),
		),
	)
	return S


// Analgesics
/datum/affliction/paracetamol_overdose
	name = "paracetamol overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Paracetamol overdose is hepatotoxic — the liver-clearance pathway saturates and metabolites accumulate as direct organ damage."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/jaundice  = 60,
		/datum/affliction_symptom/fatigue   = 70,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.5
	organ_damage_targets = list(O_LIVER)
	caused_by_chems = list(REAGENT_ID_PARACETAMOL = 60)
	caused_by_chems_organ = O_LIVER

/datum/affliction/paracetamol_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea  = 55,
				/datum/affliction_symptom/fatigue = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
			"organ_damage_per_tick" = 0.15,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea   = 75,
				/datum/affliction_symptom/jaundice = 55,
				/datum/affliction_symptom/fatigue  = 65,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.35,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea               = 90,
				/datum/affliction_symptom/jaundice             = 80,
				/datum/affliction_symptom/fatigue              = 90,
				/datum/affliction_symptom/abdominal_tenderness = 60,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 0.7,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
	)
	return S


/datum/affliction/tramadol_overdose
	name = "tramadol overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Tramadol at overdose causes serotonin-syndrome-like symptoms — agitation, tachycardia, sweating, confusion."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/jittery       = 80,
		/datum/affliction_symptom/palpitations  = 60,
		/datum/affliction_symptom/confusion     = 50,
		/datum/affliction_symptom/fever_sensation = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_TRAMADOL = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/tramadol_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery     = 60,
				/datum/affliction_symptom/palpitations = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery         = 80,
				/datum/affliction_symptom/palpitations    = 60,
				/datum/affliction_symptom/confusion       = 50,
				/datum/affliction_symptom/fever_sensation = 40,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery         = 95,
				/datum/affliction_symptom/palpitations    = 85,
				/datum/affliction_symptom/confusion       = 75,
				/datum/affliction_symptom/fever_sensation = 65,
				/datum/affliction_symptom/sharp_chest_pain = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"always_spawns" = list(/datum/affliction/tachycardia_chem),
		),
	)
	return S


// Stabilisers
/datum/affliction/tricordrazine_overdose
	name = "tricordrazine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Tricordrazine overdose is severely toxic — the broad-spectrum stabiliser becomes a broad-spectrum harm. Multi-system distress, liver damage, and weakness."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/fatigue   = 90,
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/jaundice  = 60,
		/datum/affliction_symptom/pallor    = 50,
	)
	min_symptoms = 2
	max_symptoms = 4
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.6
	organ_damage_targets = list(O_LIVER)
	caused_by_chems = list(REAGENT_ID_TRICORDRAZINE = 120)
	caused_by_chems_organ = O_LIVER

/datum/affliction/tricordrazine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue = 70,
				/datum/affliction_symptom/nausea  = 55,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"organ_damage_per_tick" = 0.2,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue  = 85,
				/datum/affliction_symptom/nausea   = 70,
				/datum/affliction_symptom/jaundice = 55,
				/datum/affliction_symptom/pallor   = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.45,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue              = 100,
				/datum/affliction_symptom/nausea               = 90,
				/datum/affliction_symptom/jaundice             = 80,
				/datum/affliction_symptom/pallor               = 75,
				/datum/affliction_symptom/abdominal_tenderness = 60,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 0.9,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
	)
	return S


// Hemostatics
/datum/affliction/myelamine_overdose
	name = "myelamine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Myelamine at overdose drives clotting past the point of utility — platelets aggregate in the small vessels, creating microthrombi while the liver works overtime clearing the breakdown products. Chest pain, fatigue, and accumulating toxin damage."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/sharp_chest_pain = 70,
		/datum/affliction_symptom/fatigue          = 60,
		/datum/affliction_symptom/palpitations     = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 0.6
	caused_by_chems = list(REAGENT_ID_MYELAMINE = 15)
	caused_by_chems_organ = O_HEART

/datum/affliction/myelamine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue     = 55,
				/datum/affliction_symptom/palpitations = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
			"organ_damage_per_tick" = 0.2,
			"organ_damage_type" = INJURY_TOXIN,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/sharp_chest_pain = 70,
				/datum/affliction_symptom/fatigue          = 60,
				/datum/affliction_symptom/palpitations     = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.4,
			"organ_damage_type" = INJURY_TOXIN,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/sharp_chest_pain    = 90,
				/datum/affliction_symptom/fatigue             = 80,
				/datum/affliction_symptom/palpitations        = 75,
				/datum/affliction_symptom/chest_pain_crushing = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 0.85,
			"organ_damage_type" = INJURY_TOXIN,
		),
	)
	return S


// Antacids
/datum/affliction/calciumcarbonate_overdose
	name = "calcium carbonate overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Excess calcium carbonate overwhelms the gut — chalky residue irritates the stomach lining, throws off electrolytes, and the kidneys strain to clear the load. Nausea and abdominal tenderness predominate."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea                = 85,
		/datum/affliction_symptom/abdominal_tenderness  = 60,
		/datum/affliction_symptom/fatigue               = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_CALCIUMCARBONATE = 24)
	caused_by_chems_organ = O_LIVER

/datum/affliction/calciumcarbonate_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(/datum/affliction_symptom/nausea = 65),
			"min_symptoms" = 1, "max_symptoms" = 1,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea               = 85,
				/datum/affliction_symptom/abdominal_tenderness = 60,
				/datum/affliction_symptom/fatigue              = 40,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea               = 100,
				/datum/affliction_symptom/abdominal_tenderness = 85,
				/datum/affliction_symptom/fatigue              = 65,
				/datum/affliction_symptom/limb_weakness        = 55,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
		),
	)
	return S


// Immune modulators
/datum/affliction/immunosuprizine_overdose
	name = "immunosuprizine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Immunosuprizine at overdose strips the immune response beyond its therapeutic window — patients become fragile to incidental infection, with rising toxin load as cellular byproducts go uncleared. The trade-off: organ rejection is held off even more aggressively, useful when a fresh transplant is teetering."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 70,
		/datum/affliction_symptom/fatigue         = 70,
		/datum/affliction_symptom/pallor          = 50,
		/datum/affliction_symptom/chills          = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 0.4
	factors = alist(BF_IMMUNE_SUPPRESSION = 0.5)
	caused_by_chems = list(REAGENT_ID_IMMUNOSUPRIZINE = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/immunosuprizine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fatigue = 55,
				/datum/affliction_symptom/chills  = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 1,
			"organ_damage_per_tick" = 0.15,
			"organ_damage_type" = INJURY_TOXIN,
			"factors" = alist(BF_IMMUNE_SUPPRESSION = 0.2),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fever_sensation = 65,
				/datum/affliction_symptom/fatigue         = 70,
				/datum/affliction_symptom/pallor          = 50,
				/datum/affliction_symptom/chills          = 40,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.3,
			"organ_damage_type" = INJURY_TOXIN,
			"factors" = alist(BF_IMMUNE_SUPPRESSION = 0.35),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/fever_sensation = 85,
				/datum/affliction_symptom/fatigue         = 90,
				/datum/affliction_symptom/pallor          = 75,
				/datum/affliction_symptom/chills          = 65,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 0.55,
			"organ_damage_type" = INJURY_TOXIN,
			"factors" = alist(BF_IMMUNE_SUPPRESSION = 0.55),
			"always_spawns" = list(/datum/affliction/wound_infection, /datum/affliction/sepsis),
		),
	)
	return S


// Alcohol antagonists
/datum/affliction/ethylredoxrazine_overdose
	name = "ethylredoxrazine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Ethylredoxrazine is a strong oxidiser — at overdose the same reactivity that scrubs ethanol turns on the body's own tissues. Liver irritation, nausea, and a general oxidative stress that wears the patient down."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea   = 75,
		/datum/affliction_symptom/jaundice = 50,
		/datum/affliction_symptom/fatigue  = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.3
	organ_damage_targets = list(O_LIVER)
	caused_by_chems = list(REAGENT_ID_ETHYLREDOXRAZINE = 30)
	caused_by_chems_organ = O_LIVER

/datum/affliction/ethylredoxrazine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(/datum/affliction_symptom/nausea = 60),
			"min_symptoms" = 1, "max_symptoms" = 1,
			"organ_damage_per_tick" = 0.1,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea   = 75,
				/datum/affliction_symptom/jaundice = 50,
				/datum/affliction_symptom/fatigue  = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"organ_damage_per_tick" = 0.25,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea   = 90,
				/datum/affliction_symptom/jaundice = 75,
				/datum/affliction_symptom/fatigue  = 75,
				/datum/affliction_symptom/abdominal_tenderness = 55,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.45,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_LIVER),
		),
	)
	return S


// Cough drops / numbing
/datum/affliction/menthol_overdose
	name = "menthol overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Menthol at concentration produces broad cold-receptor activation — chills, mild numbing, and a sluggish, drowsy state. Not directly dangerous but takes the edge off motor control."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/chills  = 80,
		/datum/affliction_symptom/drowsy  = 60,
		/datum/affliction_symptom/dizziness = 40,
	)
	min_symptoms = 1
	max_symptoms = 2
	factors = alist(BF_SLOWDOWN = 0.3)
	caused_by_chems = list(REAGENT_ID_MENTHOL = 30)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/menthol_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(/datum/affliction_symptom/chills = 60),
			"min_symptoms" = 0, "max_symptoms" = 1,
			"factors" = alist(BF_SLOWDOWN = 0.1),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/chills    = 75,
				/datum/affliction_symptom/drowsy    = 55,
				/datum/affliction_symptom/dizziness = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"factors" = alist(BF_SLOWDOWN = 0.25),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/chills    = 90,
				/datum/affliction_symptom/drowsy    = 75,
				/datum/affliction_symptom/dizziness = 60,
				/datum/affliction_symptom/cold_mottled_skin = 50,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"factors" = alist(BF_SLOWDOWN = 0.45),
		),
	)
	return S


// Radiation chems
/datum/affliction/arithrazine_overdose
	name = "arithrazine overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Arithrazine at overdose is severely tissue-damaging — the same reactivity that scrubs radiation out of the cellular machinery turns indiscriminate. Persistent tox loading, weakness, and broad organ stress."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/nausea     = 85,
		/datum/affliction_symptom/fatigue    = 70,
		/datum/affliction_symptom/jaundice   = 60,
		/datum/affliction_symptom/pallor     = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 1.0
	caused_by_chems = list(REAGENT_ID_ARITHRAZINE = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/arithrazine_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea  = 65,
				/datum/affliction_symptom/fatigue = 50,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"organ_damage_per_tick" = 0.35,
			"organ_damage_type" = INJURY_TOXIN,
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea    = 85,
				/datum/affliction_symptom/fatigue   = 70,
				/datum/affliction_symptom/jaundice  = 55,
				/datum/affliction_symptom/pallor    = 40,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.7,
			"organ_damage_type" = INJURY_TOXIN,
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/nausea     = 100,
				/datum/affliction_symptom/fatigue    = 90,
				/datum/affliction_symptom/jaundice   = 80,
				/datum/affliction_symptom/pallor     = 70,
				/datum/affliction_symptom/radiation_reading = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 1.3,
			"organ_damage_type" = INJURY_TOXIN,
		),
	)
	return S


// Plant extracts
/datum/affliction/earthsblood_overdose
	name = "earthsblood overdose"
	category = "Pharmacological"
	subcategory = "Overdose"
	chem_scaling = TRUE
	clinical_description = "Earthsblood's psychoactive component overwhelms the cortex at overdose — the same neuron-tithing that powers its healing turns aggressive. Hallucinations, confusion, and ongoing brain tissue loss. The hand-off it offers in exchange: tox, oxy, and clone damage continue to bleed off rapidly even at OD."
	progression_rate = 0
	symptom_pool = list(
		/datum/affliction_symptom/confusion       = 80,
		/datum/affliction_symptom/jittery         = 60,
		/datum/affliction_symptom/headache        = 50,
		/datum/affliction_symptom/unsteady_gait   = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.5
	organ_damage_targets = list(O_BRAIN)
	caused_by_chems = list(REAGENT_ID_EARTHSBLOOD = 15)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/earthsblood_overdose/get_stages()
	var/static/list/S = list(
		"Mild" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/jittery  = 50,
				/datum/affliction_symptom/headache = 40,
			),
			"min_symptoms" = 1, "max_symptoms" = 2,
			"organ_damage_per_tick" = 0.15,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
		),
		"Severe" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion     = 75,
				/datum/affliction_symptom/jittery       = 60,
				/datum/affliction_symptom/headache      = 50,
				/datum/affliction_symptom/unsteady_gait = 40,
			),
			"min_symptoms" = 2, "max_symptoms" = 3,
			"organ_damage_per_tick" = 0.35,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
		),
		"Critical" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/confusion           = 95,
				/datum/affliction_symptom/jittery             = 80,
				/datum/affliction_symptom/headache            = 70,
				/datum/affliction_symptom/unsteady_gait       = 60,
				/datum/affliction_symptom/pupillary_asymmetry = 50,
			),
			"min_symptoms" = 3, "max_symptoms" = 4,
			"organ_damage_per_tick" = 0.7,
			"organ_damage_type" = "internal",
			"organ_damage_targets" = list(O_BRAIN),
		),
	)
	return S
