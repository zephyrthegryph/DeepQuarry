// Hyperzine's pharmacology: side effect, overdose and the two interactions that name it.
// Families and the stage template: code/content/medical/conditions/pharmacology/_pharmacology.dm.

/datum/affliction/chem_side_effect/hyperzine_palpitations
	factors = alist(STAT_HEART_RATE = 20, STAT_BP_SYSTOLIC = 8)
	name = "stimulant tachycardia"
	clinical_description = "Hyperzine is a potent stimulant. Sub-overdose levels accelerate the heart and raise blood pressure in a noticeable way. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/palpitations = 90,
		/datum/affliction_symptom/jittery      = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_HYPERZINE = 5)
	caused_by_chems_organ = O_HEART

/datum/affliction/overdose/hyperzine
	name = "stimulant overdose"
	clinical_description = "Hyperzine at overdose drives the heart and adrenergic system past their working range. Severe tachycardia, hypertension, toxic muscle stress. Patients in this state move noticeably faster and shrug off pain — combat use is a known abuse, but the heart strain and toxin damage are real."
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
	factors = alist(STAT_SLOWDOWN = -1, STAT_ACCURACY = 20, STAT_ANALGESIA = 15, STAT_HEART_RATE = 40, STAT_BP_SYSTOLIC = 20)
	caused_by_chems = list(REAGENT_ID_HYPERZINE = 20)
	caused_by_chems_organ = O_HEART

/datum/affliction/overdose/hyperzine
	overdose_stage_data = list(
		list(list(
			/datum/affliction_symptom/palpitations = 70,
			/datum/affliction_symptom/jittery      = 60,
		), 1, 2, list("organ_damage_per_tick" = 0.3, "factors" = alist(STAT_SLOWDOWN = -0.4, STAT_ACCURACY = 8, STAT_ANALGESIA = 5, STAT_HEART_RATE = 15, STAT_BP_SYSTOLIC = 8))),
		list(list(
			/datum/affliction_symptom/palpitations     = 90,
			/datum/affliction_symptom/jittery          = 80,
			/datum/affliction_symptom/sharp_chest_pain = 50,
		), 2, 3, list("organ_damage_per_tick" = 0.7, "factors" = alist(STAT_SLOWDOWN = -0.8, STAT_ACCURACY = 15, STAT_ANALGESIA = 10, STAT_HEART_RATE = 28, STAT_BP_SYSTOLIC = 14))),
		list(list(
			/datum/affliction_symptom/palpitations        = 100,
			/datum/affliction_symptom/jittery             = 90,
			/datum/affliction_symptom/sharp_chest_pain    = 80,
			/datum/affliction_symptom/chest_pain_crushing = 50,
		), 3, 4, list("organ_damage_per_tick" = 1.4, "factors" = alist(STAT_SLOWDOWN = -1.2, STAT_ACCURACY = 25, STAT_ANALGESIA = 20, STAT_HEART_RATE = 45, STAT_BP_SYSTOLIC = 25), "always_spawns" = list(/datum/affliction/heart_damage, /datum/affliction/chem_interaction/tachycardia_chem))),
	)

/datum/affliction/chem_interaction/tachycardia_chem
	factors = alist(STAT_HEART_RATE = 30)
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

/datum/affliction/chem_interaction/cardiac_stress_interaction
	factors = alist(STAT_HEART_RATE = 25, STAT_BP_SYSTOLIC = 10)
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
