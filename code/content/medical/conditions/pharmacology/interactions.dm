// Drug interactions: two chems in the body together: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

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

/datum/affliction/chem_interaction/rezadone_arithrazine_cancel
	name = "arithrazine cancelled"
	clinical_description = "Rezadone's cellular repair undoes what arithrazine does: arithrazine has no effect while rezadone is in the body."
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_ARITHRAZINE = 0)
	caused_by_chems = list(
		REAGENT_ID_REZADONE    = 2,
		REAGENT_ID_ARITHRAZINE = 2,
	)
	caused_by_chems_organ = O_LIVER

/datum/affliction/chem_interaction/myelamine_cordradaxon_conflict
	name = "clotting against repair"
	clinical_description = "Myelamine's clotting and cordradaxon's cardiac repair work against each other: both work at half strength while the two are in the body together."
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(
		REAGENT_ID_MYELAMINE   = 0.5,
		REAGENT_ID_CORDRADAXON = 0.5,
	)
	caused_by_chems = list(
		REAGENT_ID_MYELAMINE   = 2,
		REAGENT_ID_CORDRADAXON = 2,
	)
	caused_by_chems_organ = O_HEART

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
	factors = alist(STAT_SLOWDOWN = 1.5, STAT_ACCURACY = -25, STAT_MOTOR_CONTROL = 0.94, STAT_O2_SAT = -8, STAT_RESP_RATE = -6)
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

/datum/affliction/chem_interaction/calcium_antitoxin_binding
	name = "antitoxin binding"
	clinical_description = "Calcium carbonate binds Dylovene in the gut and the blood. Dylovene treats poisoning at half its normal effectiveness while both are in the body."
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_ANTITOXIN = 0.5)
	caused_by_chems = list(
		REAGENT_ID_CALCIUMCARBONATE = 2,
		REAGENT_ID_ANTITOXIN        = 2,
	)
	caused_by_chems_organ = O_LIVER

/datum/affliction/chem_interaction/carthatoline_iron_binding
	name = "iron binding"
	clinical_description = "Carthatoline strips iron out of the blood along with the toxins. Iron saline restores blood volume at half its normal rate while both are in the body."
	min_symptoms = 0
	max_symptoms = 0
	interferes_with = list(REAGENT_ID_IRONSALINE = 0.5)
	caused_by_chems = list(
		REAGENT_ID_IRONSALINE   = 2,
		REAGENT_ID_CARTHATOLINE = 2,
	)
	caused_by_chems_organ = O_LIVER

/datum/affliction/chem_interaction/adranol_anticonvulsant_sedation
	name = "stacked drowsiness"
	clinical_description = "Adranol and an anticonvulsant together stack their sedating effects: the patient is noticeably drowsy and slow. Resolves when either chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy = 100,
	)
	min_symptoms = 1
	max_symptoms = 1
	factors = alist(STAT_SLOWDOWN = 0.3, STAT_MOTOR_CONTROL = 0.97)
	spontaneous_emotes = list("yawn", "nod off")
	spontaneous_emote_prob = 4
	caused_by_chems = list(
		REAGENT_ID_ADRANOL        = 2,
		REAGENT_ID_ANTICONVULSANT = 2,
	)
	caused_by_chems_organ = O_BRAIN
