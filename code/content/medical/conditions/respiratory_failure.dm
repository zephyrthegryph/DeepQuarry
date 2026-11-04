// Damage-emergent: this condition IS lungs at >70% damage. It auto-
// spawns when lungs cross threshold and auto-cures when they recover.
// No independent severity progression — the lungs' damage IS the
// severity. The condition stacks hypoxia directly so a patient with
// failing lungs starts dying.
/datum/affliction/respiratory_failure
	name = "respiratory failure"
	category = "Chest"
	clinical_description = "The lungs can no longer oxygenate the blood. Without oxygen the rest of the body begins to suffocate from the inside."
	progression_rate = 0  // no self-progression; tracks lung damage
	// Respirodaxon is the targeted lung-repair drug. Dexalin-plus
	// supplies oxygen while the lungs recover.
	treated_by = list(TREAT_RESPIRATORY = 1.2, TREAT_OXYGENATION = 0.4)
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 95,
		/datum/affliction_symptom/cyanosis          = 90,
		/datum/affliction_symptom/confusion         = 70,
		/datum/affliction_symptom/pallor            = 70,
	)
	min_symptoms = 2
	max_symptoms = 4
	factors = alist(STAT_SLOWDOWN = 2.5, STAT_ACCURACY = -50, STAT_MOTOR_CONTROL = 0.92, STAT_ACTION_BLOCKS = ACTION_BLOCK_SPEECH, STAT_HEART_RATE = 20, STAT_RESP_RATE = -8, STAT_GAS_EXCHANGE = 0.15)
	spontaneous_emotes = list("gasp", "collapse", "wheeze")
	spontaneous_emote_prob = 10
