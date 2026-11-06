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
	factors = alist(STAT_IMMUNE_SUPPRESSION = 0.5)
	caused_by_chems = list(REAGENT_ID_IMMUNOSUPRIZINE = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/immunosuprizine
	overdose_stage_data = list(
		list(list(
			/datum/affliction_symptom/fatigue = 55,
			/datum/affliction_symptom/chills  = 40,
		), 1, 1, list("organ_damage_per_tick" = 0.15, "organ_damage_type" = INJURY_TOXIN, "factors" = alist(STAT_IMMUNE_SUPPRESSION = 0.2))),
		list(list(
			/datum/affliction_symptom/fever_sensation = 65,
			/datum/affliction_symptom/fatigue         = 70,
			/datum/affliction_symptom/pallor          = 50,
			/datum/affliction_symptom/chills          = 40,
		), 2, 3, list("organ_damage_per_tick" = 0.3, "organ_damage_type" = INJURY_TOXIN, "factors" = alist(STAT_IMMUNE_SUPPRESSION = 0.35))),
		list(list(
			/datum/affliction_symptom/fever_sensation = 85,
			/datum/affliction_symptom/fatigue         = 90,
			/datum/affliction_symptom/pallor          = 75,
			/datum/affliction_symptom/chills          = 65,
		), 3, 4, list("organ_damage_per_tick" = 0.55, "organ_damage_type" = INJURY_TOXIN, "factors" = alist(STAT_IMMUNE_SUPPRESSION = 0.55), "always_spawns" = list(/datum/affliction/wound_infection, /datum/affliction/sepsis))),
	)
