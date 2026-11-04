/datum/affliction/sepsis
	name = "sepsis"
	category = "Infection"
	clinical_description = "A systemic inflammatory response to bacterial invasion of the bloodstream. The whole body is fighting, and losing."
	progression_rate = 0.7
	// Sepsis needs aggressive antibiotic coverage: corophizine's wide
	// spectrum + spaceacillin together. Inaprovaline supports BP.
	treated_by = list(TREAT_ANTIMICROBIAL = 1.05, TREAT_CIRCULATORY = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 80,
		/datum/affliction_symptom/chills          = 70,
		/datum/affliction_symptom/confusion       = 50,
		/datum/affliction_symptom/pallor          = 50,
		/datum/affliction_symptom/fatigue         = 60,
		/datum/affliction_symptom/short_breath    = 40,
	)
	min_symptoms = 2
	max_symptoms = 4
	// Pulse derives from elevated body temp; BP drop from vasodilation
	// is real and the only thing not modelled elsewhere.
	factors = alist(STAT_SLOWDOWN = 0.6, STAT_ACCURACY = -10, STAT_BP_SYSTOLIC = -15, STAT_TEMPERATURE = 3.5)
	spontaneous_emotes = list("shudder", "cough", "groan")
	spontaneous_emote_prob = 4
	// Sepsis is multi-organ inflammation; the kidneys take the first hit.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 1
	organ_damage_targets = list(O_KIDNEYS)
