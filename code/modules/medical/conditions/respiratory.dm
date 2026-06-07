// Respiratory chain — second terminal sink (after cardiac_arrest).
//
// Three entry points feeding respiratory_failure:
//   pulmonary_contusion (blunt chest)  ──┐
//   tension_pneumothorax (sharp chest) ──┼──→ respiratory_failure (terminal)
//   airway_burn (burn near head)       ──┘
//
// Different cures depending on entry point — burns need kelotane/dexalin,
// blunt trauma heals with rest+bicaridine, pneumothorax needs surgery
// (until built, dexalin stalls but doesn't cure).

/datum/medical_issue/condition/pulmonary_contusion
	name = "pulmonary contusion"
	category = "Chest"
	clinical_description = "Bruised lung tissue from a heavy chest impact. Breathing grows harder as fluid accumulates in the lung."
	progression_rate = 1.0
	// Mild lung trauma — respirodaxon repairs the bruised tissue
	// directly; dexalin supports oxygenation while it heals.
	cured_by = list(REAGENT_ID_RESPIRODAXON = 0.8, REAGENT_ID_DEXALIN = 0.4)
	organ_damage_threshold = 70
	organ_damage_type = "internal"
	organ_damage_per_tick = 1.5
	organ_damage_targets = list(O_LUNGS)
	symptom_pool = list(
		/datum/medical_symptom/wet_cough         = 70,
		/datum/medical_symptom/labored_breathing = 70,
		/datum/medical_symptom/short_breath      = 60,
		/datum/medical_symptom/sharp_chest_pain  = 60,
		/datum/medical_symptom/pallor            = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	mechanical_effects = list(
		"slowdown" = 0.6,
		"spontaneous_emotes" = list("cough", "gasp"),
		"spontaneous_emote_prob" = 4,
	)

/datum/medical_issue/condition/pulmonary_contusion/get_vital_effects()
	var/static/list/L = list("resp_mod" = 6, "o2_sat_mod" = -8)
	return L

// Driven by blunt chest damage. The harder the chest's been hit, the
// faster the contusion compounds.
/datum/medical_issue/condition/pulmonary_contusion/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
		if(chest)
			. *= dq_damage_scale(chest.brute_dam, 10, 60, 0.6, 2.5)

/datum/medical_issue/condition/tension_pneumothorax
	name = "tension pneumothorax"
	category = "Chest"
	clinical_description = "Air trapped in the chest cavity is collapsing the lung and pushing on the heart. Each breath makes it worse."
	progression_rate = 2.0
	// Without surgery, antibiotics + dexalin just slow it. Real cure
	// requires surgical decompression — to be built later.
	cured_by = list(REAGENT_ID_DEXALIN = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/labored_breathing = 90,
		/datum/medical_symptom/sharp_chest_pain  = 80,
		/datum/medical_symptom/cyanosis          = 60,
		/datum/medical_symptom/pallor            = 60,
		/datum/medical_symptom/confusion         = 30,
	)
	min_symptoms = 2
	max_symptoms = 4
	mechanical_effects = list(
		"slowdown" = 1.5,
		"accuracy_penalty" = 20,
		"spontaneous_emotes" = list("gasp", "wince", "collapse"),
		"spontaneous_emote_prob" = 6,
	)
	// Damages lungs above moderate severity. Once lungs hit 70%, the
	// emergent system spawns respiratory_failure on top.
	organ_damage_threshold = 50
	organ_damage_type = "internal"
	organ_damage_per_tick = 3
	organ_damage_targets = list(O_LUNGS)

/datum/medical_issue/condition/tension_pneumothorax/get_vital_effects()
	var/static/list/L = list("resp_mod" = 10, "o2_sat_mod" = -15, "bp_sys_mod" = -15)
	return L

/datum/medical_issue/condition/tension_pneumothorax/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
		if(chest)
			// Sharp chest damage is the actual mechanism — but use total
			// brute_dam as a proxy (engine doesn't distinguish post-hoc).
			. *= dq_damage_scale(chest.brute_dam, 15, 60, 0.7, 2.5)

/datum/medical_issue/condition/airway_burn
	name = "airway burn"
	category = "Chest"
	clinical_description = "An inhalation injury — heat and smoke have scorched the upper airway, and the tissue is swelling in response."
	progression_rate = 1.0
	// Burn-specialised dermaline / kelotane treat the airway burn itself;
	// respirodaxon repairs the underlying lung tissue once they've cooled.
	cured_by = list(REAGENT_ID_DERMALINE = 1.0, REAGENT_ID_KELOTANE = 0.6, REAGENT_ID_RESPIRODAXON = 0.4)
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 2
	organ_damage_targets = list(O_LUNGS)
	symptom_pool = list(
		/datum/medical_symptom/wheeze            = 80,
		/datum/medical_symptom/labored_breathing = 70,
		/datum/medical_symptom/short_breath      = 60,
		/datum/medical_symptom/cyanosis          = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	mechanical_effects = list(
		"slowdown" = 0.8,
		"spontaneous_emotes" = list("cough", "wheeze", "gasp"),
		"spontaneous_emote_prob" = 5,
	)

/datum/medical_issue/condition/airway_burn/get_vital_effects()
	var/static/list/L = list("resp_mod" = 8, "o2_sat_mod" = -10)
	return L

// Driven by burn damage on the head (face/airway).
/datum/medical_issue/condition/airway_burn/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
		if(head)
			. *= dq_damage_scale(head.burn_dam, 10, 50, 0.7, 2.4)

// Damage-emergent: this condition IS lungs at >70% damage. It auto-
// spawns when lungs cross threshold and auto-cures when they recover.
// No independent severity progression — the lungs' damage IS the
// severity. The condition stacks oxyloss directly so a patient with
// failing lungs starts dying.
/datum/medical_issue/condition/respiratory_failure
	name = "respiratory failure"
	category = "Chest"
	clinical_description = "The lungs can no longer oxygenate the blood. Without oxygen the rest of the body begins to suffocate from the inside."
	progression_rate = 0  // no self-progression; tracks lung damage
	// Respirodaxon is the targeted lung-repair drug. Dexalin-plus
	// supplies oxygen while the lungs recover.
	cured_by = list(REAGENT_ID_RESPIRODAXON = 1.2, REAGENT_ID_DEXALINP = 0.4)
	symptom_pool = list(
		/datum/medical_symptom/labored_breathing = 95,
		/datum/medical_symptom/cyanosis          = 90,
		/datum/medical_symptom/confusion         = 70,
		/datum/medical_symptom/pallor            = 70,
	)
	min_symptoms = 2
	max_symptoms = 4
	mechanical_effects = list(
		"slowdown" = 2.5,
		"accuracy_penalty" = 50,
		"drop_held_prob" = 8,
		"block_typing" = TRUE,
		"spontaneous_emotes" = list("gasp", "collapse", "wheeze"),
		"spontaneous_emote_prob" = 10,
	)
	// Heavy oxyloss while present.
	organ_damage_threshold = 0
	organ_damage_type = "oxy"
	organ_damage_per_tick = 5

/datum/medical_issue/condition/respiratory_failure/get_vital_effects()
	var/static/list/L = list("resp_mod" = -8, "o2_sat_mod" = -30, "pulse_mod" = 20)
	return L
