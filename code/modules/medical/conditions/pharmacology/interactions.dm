// Drug interactions: two chems in the body together: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/chem_interaction/tachycardia_chem
	factors = alist(BF_HEART_RATE = 30)
	name = "drug-induced tachycardia"
	clinical_description = "Inaprovaline (depressant) and hyperzine (stimulant) given together produce erratic, fast heart rate. Resolves when either chem clears."
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

/datum/affliction/chem_interaction/bicaridine_antibiotic_interference
	name = "antibiotic interference"
	clinical_description = "Bicaridine's antiplatelet activity interferes with spaceacillin absorption. Spaceacillin treats infections at 40% of its normal effectiveness while both are in the body."
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_SPACEACILLIN = 0.4)
	caused_by_chems = list(
		REAGENT_ID_BICARIDINE   = 2,
		REAGENT_ID_SPACEACILLIN = 2,
	)
	caused_by_chems_organ = O_LIVER

/datum/affliction/chem_interaction/opioid_co_administration
	name = "compound CNS depression"
	clinical_description = "Combining tramadol and oxycodone produces additive CNS depression — drowsiness, respiratory suppression, and slowed reflexes well beyond either alone. Resolves when either chem clears."
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

/datum/affliction/chem_interaction/antibiotic_cross_interference
	name = "antibiotic cross-interference"
	clinical_description = "Spaceacillin and corophizine target similar bacterial mechanisms; given together they compete for absorption and both work at reduced effectiveness."
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

/datum/affliction/chem_interaction/peridaxon_daxon_synergy
	name = "potentiated organ repair"
	clinical_description = "Peridaxon's generic organ-repair pathway primes tissue receptors so the targeted daxon-family drugs (cordradaxon, respirodaxon, hepanephrodaxon, gastirodaxon) work faster. A documented synergy."
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

/datum/affliction/chem_interaction/synaptizine_alkysine_potentiation
	name = "potentiated neurorepair"
	clinical_description = "Synaptizine opens the blood-brain barrier slightly, letting alkysine reach more damaged neural tissue per dose. The chems work together better than apart."
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_ALKYSINE = 1.5)
	caused_by_chems = list(
		REAGENT_ID_SYNAPTIZINE = 2,
		REAGENT_ID_ALKYSINE    = 2,
	)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/chem_interaction/cardiac_stress_interaction
	factors = alist(BF_HEART_RATE = 25, BF_BP_SYSTOLIC = 10)
	name = "cardiac stress"
	clinical_description = "Stimulant-driven tachycardia compounds the load on a heart that's actively trying to repair itself. Hyperzine and cordradaxon together stress the cardiac muscle even as the latter tries to heal it."
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
