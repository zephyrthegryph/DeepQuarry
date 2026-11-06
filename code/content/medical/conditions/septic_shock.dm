/datum/affliction/septic_shock
	name = "septic shock"
	category = "Infection"
	clinical_description = "Sepsis past the point of compensation: blood pressure collapses and organs begin to fail."
	progression_rate = 1.0
	// Late-stage sepsis needs the strongest antibiotic + BP support +
	// red-cell support to drag the patient back.
	treated_by = list(TREAT_ANTIMICROBIAL = 0.75, TREAT_CIRCULATORY = 0.5, TREAT_BLOOD_RESTORE = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/pallor          = 90,
		/datum/affliction_symptom/confusion       = 70,
		/datum/affliction_symptom/dizziness       = 70,
		/datum/affliction_symptom/short_breath    = 60,
		/datum/affliction_symptom/chills          = 60,
	)
	min_symptoms = 2
	max_symptoms = 4
	// Temp pushed by actual bodytemperature mutation; BP collapse from
	// septic vasodilation is real and not otherwise modelled.
	factors = alist(STAT_SLOWDOWN = 1.5, STAT_ACCURACY = -25, STAT_MOTOR_CONTROL = 0.96, STAT_BP_SYSTOLIC = -45, STAT_BP_DIASTOLIC = -25, STAT_O2_SAT = -10)
	spontaneous_emotes = list("collapse", "shudder", "groan")
	spontaneous_emote_prob = 6
	// Septic shock: multi-organ failure. Liver and kidneys go first;
	// when they're max-damaged the patient's reagent metabolism breaks
	// and hypoxia builds on top.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 4
	organ_damage_targets = list(O_LIVER, O_KIDNEYS)
