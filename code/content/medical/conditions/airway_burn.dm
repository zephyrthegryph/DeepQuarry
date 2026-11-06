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
	factors = alist(STAT_SLOWDOWN = 0.8, STAT_O2_SAT = -10, STAT_RESP_RATE = 8)
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
