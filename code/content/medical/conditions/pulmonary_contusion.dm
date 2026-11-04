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
	factors = alist(STAT_SLOWDOWN = 0.6, STAT_O2_SAT = -8, STAT_RESP_RATE = 6)
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
