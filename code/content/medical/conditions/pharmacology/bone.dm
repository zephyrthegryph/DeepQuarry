// Bone drugs: pharmacological side effects. Families and the stage template: _pharmacology.dm.

/datum/affliction/chem_side_effect/osteodaxon_ache
	name = "osteodaxon bone ache"
	clinical_description = "Osteodaxon forces bone growth, and the growing bone aches deep inside for as long as the drug is in the blood. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/bone_ache = 100,
	)
	min_symptoms = 1
	max_symptoms = 1
	factors = alist(STAT_PAIN = 4)
	caused_by_chems = list(REAGENT_ID_OSTEODAXON = 1)
	caused_by_chems_organ = O_LIVER
