// Drawbacks and interactions of the organ, brain, circulation and infection drugs (cordradaxon, respirodaxon, hepanephrodaxon, gastirodaxon,
// norepinephrine, epinephrine, synaptizine, dexalin plus). Strains and hidden readings are declared on the reagents themselves
// (code/content/reagents/drug_profile.dm); what a drug adds is here. Families and the stage template: _pharmacology.dm.

// --- Side effects -----------------------------------------------------------------------------------------------------------

/datum/affliction/chem_side_effect/respirodaxon_airway_sensitivity
	name = "respirodaxon airway sensitivity"
	clinical_description = "The airway that respirodaxon is mending is tender. While the drug is in the blood, smoke and gas in the air reach the lungs more easily and gas exchange runs a little poorer. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/wet_cough = 60,
		/datum/affliction_symptom/wheeze    = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	factors = alist(STAT_GAS_EXCHANGE = 0.9)
	caused_by_chems = list(REAGENT_ID_RESPIRODAXON = 1)
	caused_by_chems_organ = O_LUNGS

/datum/affliction/nausea/hepanephrodaxon
	name = "hepanephrodaxon nausea"
	clinical_description = "Hepanephrodaxon makes the stomach turn while the liver and kidneys mend. It lasts as long as the drug is in the blood; an antiemetic (calcium carbonate) settles it."
	progression_rate = 0
	caused_by_chems = list(REAGENT_ID_HEPANEPHRODAXON = 1)

/datum/affliction/chem_side_effect/norepinephrine_numbness
	name = "norepinephrine numbness"
	clinical_description = "Norepinephrine clamps the vessels of the limbs to hold up the blood pressure, and the arms and legs go numb. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/numbness_arm = 80,
		/datum/affliction_symptom/numbness_leg = 70,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_NOREPINEPHRINE = 1)
	caused_by_chems_organ = O_HEART

// --- Interactions -----------------------------------------------------------------------------------------------------------

/datum/affliction/chem_interaction/epinephrine_synaptizine_tachycardia
	name = "adrenergic overload"
	clinical_description = "Epinephrine and synaptizine together drive the heart into a fast, irritable rhythm: palpitations, a racing pulse and an unstable rhythm that degenerates sooner. Never give them together. Resolves when either chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/palpitations = 95,
		/datum/affliction_symptom/short_breath = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	factors = alist(STAT_HEART_RATE = 35, STAT_BP_SYSTOLIC = 15, STAT_CARDIAC_IRRITABILITY = 2)
	caused_by_chems = list(
		REAGENT_ID_EPINEPHRINE = 1,
		REAGENT_ID_SYNAPTIZINE = 1,
	)
	caused_by_chems_organ = O_HEART

/datum/affliction/chem_interaction/dexalinp_dylovene_cyanide
	name = "cyanide antidote"
	clinical_description = "Dexalin plus carries oxygen to the starved tissues while dylovene binds the cyanide: together they cure cyanide poisoning. Either alone only buys time."
	min_symptoms = 0
	max_symptoms = 0
	od_cures_externally = list(/datum/affliction/poisoning/cyanide = 6)
	caused_by_chems = list(
		REAGENT_ID_DEXALINP    = 2,
		REAGENT_ID_ANTITOXIN   = 2,
	)
	caused_by_chems_organ = O_LIVER
