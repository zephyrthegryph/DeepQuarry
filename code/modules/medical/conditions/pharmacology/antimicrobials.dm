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

/datum/affliction/overdose/spaceacillin
	name = "spaceacillin overdose"
	clinical_description = "Spaceacillin overdose produces broad GI disturbance and mild liver stress."
	symptom_pool = list(
		/datum/affliction_symptom/nausea  = 70,
		/datum/affliction_symptom/fatigue = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_SPACEACILLIN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/spaceacillin/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/nausea = 55), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/nausea  = 75,
			/datum/affliction_symptom/fatigue = 50,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/nausea   = 90,
			/datum/affliction_symptom/fatigue  = 75,
			/datum/affliction_symptom/jaundice = 55,
		), 2, 3, list("always_spawns" = list(/datum/affliction/toxic_poisoning))),
	)
	return S

/datum/affliction/overdose/corophizine
	name = "corophizine overdose"
	clinical_description = "Corophizine at overdose is markedly more harsh than therapeutic dose — severe GI symptoms, liver irritation, and weakness."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 90,
		/datum/affliction_symptom/jaundice  = 50,
		/datum/affliction_symptom/fatigue   = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_COROPHIZINE = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/corophizine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/nausea  = 70,
			/datum/affliction_symptom/fatigue = 45,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/nausea   = 90,
			/datum/affliction_symptom/jaundice = 50,
			/datum/affliction_symptom/fatigue  = 60,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/nausea               = 100,
			/datum/affliction_symptom/jaundice             = 75,
			/datum/affliction_symptom/fatigue              = 80,
			/datum/affliction_symptom/abdominal_tenderness = 55,
		), 3, 4, list("always_spawns" = list(/datum/affliction/toxic_poisoning))),
	)
	return S

/datum/affliction/overdose/immunosuprizine
	name = "immunosuprizine overdose"
	clinical_description = "Immunosuprizine at overdose strips the immune response beyond its therapeutic window — patients become fragile to incidental infection, with rising toxin load as cellular byproducts go uncleared. The trade-off: organ rejection is held off even more aggressively, useful when a fresh transplant is teetering."
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

/datum/affliction/overdose/immunosuprizine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/fatigue = 55,
			/datum/affliction_symptom/chills  = 40,
		), 1, 1, list("organ_damage_per_tick" = 0.15, "organ_damage_type" = INJURY_TOXIN, "factors" = alist(BF_IMMUNE_SUPPRESSION = 0.2))),
		chem_stage(list(
			/datum/affliction_symptom/fever_sensation = 65,
			/datum/affliction_symptom/fatigue         = 70,
			/datum/affliction_symptom/pallor          = 50,
			/datum/affliction_symptom/chills          = 40,
		), 2, 3, list("organ_damage_per_tick" = 0.3, "organ_damage_type" = INJURY_TOXIN, "factors" = alist(BF_IMMUNE_SUPPRESSION = 0.35))),
		chem_stage(list(
			/datum/affliction_symptom/fever_sensation = 85,
			/datum/affliction_symptom/fatigue         = 90,
			/datum/affliction_symptom/pallor          = 75,
			/datum/affliction_symptom/chills          = 65,
		), 3, 4, list("organ_damage_per_tick" = 0.55, "organ_damage_type" = INJURY_TOXIN, "factors" = alist(BF_IMMUNE_SUPPRESSION = 0.55), "always_spawns" = list(/datum/affliction/wound_infection, /datum/affliction/sepsis))),
	)
	return S
