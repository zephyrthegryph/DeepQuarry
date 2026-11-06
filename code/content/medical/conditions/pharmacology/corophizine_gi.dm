// Antibiotics and immune modulators: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/chem_side_effect/corophizine_gi
	name = "corophizine GI upset"
	clinical_description = "Corophizine is wide-spectrum and effective but its disruption of normal gut flora causes significant GI symptoms during treatment. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/nausea  = 80,
		/datum/affliction_symptom/fatigue = 50,
		/datum/affliction_symptom/pallor  = 30,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_COROPHIZINE = 5)
	caused_by_chems_organ = O_LIVER
