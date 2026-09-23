// Respiratory chain — second terminal sink (after cardiac_arrest).
//
// Entry points feeding respiratory_failure:
//   pulmonary_contusion (blunt chest)  ──┐
//   pneumothorax (sharp chest)         ──┼──→ respiratory_failure (terminal)
//   airway_burn (burn near head)       ──┘
//
// Different cures depending on entry point — burns need kelotane/dexalin
// (and a swelling airway, airway_edema, needs a vasopressor), blunt trauma
// heals with rest+bicaridine. Pneumothorax, airway and arrest afflictions
// live in vital_systems.dm.

/datum/affliction/pulmonary_contusion
	name = "pulmonary contusion"
	category = "Chest"
	clinical_description = "Bruised lung tissue from a heavy chest impact. Breathing grows harder as fluid accumulates in the lung."
	progression_rate = 1.0
	// Mild lung trauma — respirodaxon repairs the bruised tissue
	// directly; dexalin supports oxygenation while it heals.
	treated_by = list(TREAT_RESPIRATORY = 0.8, TREAT_OXYGENATION = 0.6)
	organ_damage_threshold = 70
	organ_damage_type = "internal"
	organ_damage_per_tick = 1.5
	organ_damage_targets = list(O_LUNGS)
	symptom_pool = list(
		/datum/affliction_symptom/wet_cough         = 70,
		/datum/affliction_symptom/labored_breathing = 70,
		/datum/affliction_symptom/short_breath      = 60,
		/datum/affliction_symptom/sharp_chest_pain  = 60,
		/datum/affliction_symptom/pallor            = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 0.6, BF_O2_SAT = -8, BF_RESP_RATE = 6)
	spontaneous_emotes = list("cough", "gasp")
	spontaneous_emote_prob = 4

// Driven by blunt chest damage. The harder the chest's been hit, the
// faster the contusion compounds.
/datum/affliction/pulmonary_contusion/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
		if(chest)
			. *= dq_damage_scale(chest.get_trauma(), 10, 60, 0.6, 2.5)

/datum/affliction/airway_burn
	name = "airway burn"
	category = "Chest"
	clinical_description = "An inhalation injury — heat and smoke have scorched the upper airway, and the tissue is swelling in response."
	progression_rate = 1.0
	// Burn-specialised dermaline / kelotane treat the airway burn itself;
	// respirodaxon repairs the underlying lung tissue once they've cooled.
	treated_by = list(TREAT_BURN_CARE = 1.0, TREAT_RESPIRATORY = 0.4)
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 2
	organ_damage_targets = list(O_LUNGS)
	symptom_pool = list(
		/datum/affliction_symptom/wheeze            = 80,
		/datum/affliction_symptom/labored_breathing = 70,
		/datum/affliction_symptom/short_breath      = 60,
		/datum/affliction_symptom/cyanosis          = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 0.8, BF_O2_SAT = -10, BF_RESP_RATE = 8)
	spontaneous_emotes = list("cough", "wheeze", "gasp")
	spontaneous_emote_prob = 5

// Driven by burn damage on the head (face/airway).
/datum/affliction/airway_burn/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
		if(head)
			. *= dq_damage_scale(head.get_burn(), 10, 50, 0.7, 2.4)

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
	factors = alist(BF_SLOWDOWN = 2.5, BF_ACCURACY = -50, BF_MOTOR_CONTROL = 0.92, BF_ACTION_BLOCKS = ACTION_BLOCK_SPEECH, BF_HEART_RATE = 20, BF_RESP_RATE = -8, BF_GAS_EXCHANGE = 0.15)
	spontaneous_emotes = list("gasp", "collapse", "wheeze")
	spontaneous_emote_prob = 10

