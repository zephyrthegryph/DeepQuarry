// Analgesics and numbing agents: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/chem_side_effect/oxycodone_drowsy
	name = "opioid drowsiness"
	clinical_description = "Oxycodone's analgesic effect comes paired with CNS depression. Patients on therapeutic-dose opioid are slower, drowsy, and at risk of respiratory suppression. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy           = 90,
		/datum/affliction_symptom/short_breath     = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	factors = alist(BF_SLOWDOWN = 0.4, BF_MOTOR_CONTROL = 0.98)
	spontaneous_emotes = list("yawn", "nod off")
	spontaneous_emote_prob = 4
	caused_by_chems = list(REAGENT_ID_OXYCODONE = 5)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/chem_side_effect/tramadol_nausea
	name = "tramadol nausea"
	clinical_description = "Tramadol is a common analgesic but its action on serotonin receptors causes mild nausea and dizziness in many patients. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/dizziness = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_TRAMADOL = 8)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/oxycodone
	name = "opioid overdose"
	clinical_description = "Oxycodone at overdose causes profound CNS depression — the patient may stop breathing entirely. Pinpoint pupils, slow heart, shallow respirations. The same effect produces near-total pain immunity and significant stun resistance — sometimes worth the risk when working through a major procedure under fire."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy            = 95,
		/datum/affliction_symptom/labored_breathing = 85,
		/datum/affliction_symptom/cyanosis          = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 2, BF_ACCURACY = -40, BF_MOTOR_CONTROL = 0.9, BF_DISABLE_DURATION = 0.5, BF_ANALGESIA = 50, BF_HEART_RATE = -15, BF_O2_SAT = -20, BF_RESP_RATE = -10)
	spontaneous_emotes = list("collapse", "yawn", "fall")
	spontaneous_emote_prob = 10
	caused_by_chems = list(REAGENT_ID_OXYCODONE = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/oxycodone/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/drowsy       = 75,
			/datum/affliction_symptom/short_breath = 50,
		), 1, 2, list("factors" = alist(BF_SLOWDOWN = 0.6, BF_ACCURACY = -10, BF_DISABLE_DURATION = 0.85, BF_ANALGESIA = 20, BF_HEART_RATE = -5, BF_O2_SAT = -6, BF_RESP_RATE = -3), "spontaneous_emotes" = list("yawn"), "spontaneous_emote_prob" = 3)),
		chem_stage(list(
			/datum/affliction_symptom/drowsy            = 90,
			/datum/affliction_symptom/labored_breathing = 80,
			/datum/affliction_symptom/dizziness         = 50,
		), 2, 3, list("factors" = alist(BF_SLOWDOWN = 1.4, BF_ACCURACY = -25, BF_MOTOR_CONTROL = 0.95, BF_DISABLE_DURATION = 0.7, BF_ANALGESIA = 37.5, BF_HEART_RATE = -10, BF_O2_SAT = -14, BF_RESP_RATE = -7), "spontaneous_emotes" = list("yawn", "nod off"), "spontaneous_emote_prob" = 6)),
		chem_stage(list(
			/datum/affliction_symptom/drowsy            = 100,
			/datum/affliction_symptom/labored_breathing = 100,
			/datum/affliction_symptom/cyanosis          = 85,
			/datum/affliction_symptom/cold_mottled_skin = 50,
		), 3, 4, list("factors" = alist(BF_SLOWDOWN = 2.4, BF_ACCURACY = -50, BF_MOTOR_CONTROL = 0.88, BF_DISABLE_DURATION = 0.5, BF_ANALGESIA = 50, BF_HEART_RATE = -18, BF_O2_SAT = -25, BF_RESP_RATE = -12), "spontaneous_emotes" = list("collapse", "yawn", "fall"), "spontaneous_emote_prob" = 12, "always_spawns" = list(/datum/affliction/respiratory_arrest))),
	)
	return S

/datum/affliction/overdose/tramadol
	name = "tramadol overdose"
	clinical_description = "Tramadol at overdose causes serotonin-syndrome-like symptoms — agitation, tachycardia, sweating, confusion."
	symptom_pool = list(
		/datum/affliction_symptom/jittery       = 80,
		/datum/affliction_symptom/palpitations  = 60,
		/datum/affliction_symptom/confusion     = 50,
		/datum/affliction_symptom/fever_sensation = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_TRAMADOL = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/tramadol/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/jittery      = 60,
			/datum/affliction_symptom/palpitations = 40,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/jittery         = 80,
			/datum/affliction_symptom/palpitations    = 60,
			/datum/affliction_symptom/confusion       = 50,
			/datum/affliction_symptom/fever_sensation = 40,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/jittery          = 95,
			/datum/affliction_symptom/palpitations     = 85,
			/datum/affliction_symptom/confusion        = 75,
			/datum/affliction_symptom/fever_sensation  = 65,
			/datum/affliction_symptom/sharp_chest_pain = 50,
		), 3, 4, list("always_spawns" = list(/datum/affliction/chem_interaction/tachycardia_chem))),
	)
	return S

/datum/affliction/overdose/paracetamol
	name = "paracetamol overdose"
	clinical_description = "Paracetamol overdose is hepatotoxic — the liver-clearance pathway saturates and metabolites accumulate as direct organ damage."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/jaundice  = 60,
		/datum/affliction_symptom/fatigue   = 70,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.5
	organ_damage_targets = list(O_LIVER)
	caused_by_chems = list(REAGENT_ID_PARACETAMOL = 60)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/paracetamol/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/nausea  = 55,
			/datum/affliction_symptom/fatigue = 50,
		), 1, 1, list("organ_damage_per_tick" = 0.15, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
		chem_stage(list(
			/datum/affliction_symptom/nausea   = 75,
			/datum/affliction_symptom/jaundice = 55,
			/datum/affliction_symptom/fatigue  = 65,
		), 2, 3, list("organ_damage_per_tick" = 0.35, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
		chem_stage(list(
			/datum/affliction_symptom/nausea               = 90,
			/datum/affliction_symptom/jaundice             = 80,
			/datum/affliction_symptom/fatigue              = 90,
			/datum/affliction_symptom/abdominal_tenderness = 60,
		), 3, 4, list("organ_damage_per_tick" = 0.7, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
	)
	return S

/datum/affliction/overdose/menthol
	name = "menthol overdose"
	clinical_description = "Menthol at concentration produces broad cold-receptor activation — chills, mild numbing, and a sluggish, drowsy state. Not directly dangerous but takes the edge off motor control."
	symptom_pool = list(
		/datum/affliction_symptom/chills  = 80,
		/datum/affliction_symptom/drowsy  = 60,
		/datum/affliction_symptom/dizziness = 40,
	)
	min_symptoms = 1
	max_symptoms = 2
	factors = alist(BF_SLOWDOWN = 0.3)
	caused_by_chems = list(REAGENT_ID_MENTHOL = 30)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/menthol/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/chills = 60), 0, 1, list("factors" = alist(BF_SLOWDOWN = 0.1))),
		chem_stage(list(
			/datum/affliction_symptom/chills    = 75,
			/datum/affliction_symptom/drowsy    = 55,
			/datum/affliction_symptom/dizziness = 40,
		), 1, 2, list("factors" = alist(BF_SLOWDOWN = 0.25))),
		chem_stage(list(
			/datum/affliction_symptom/chills            = 90,
			/datum/affliction_symptom/drowsy            = 75,
			/datum/affliction_symptom/dizziness         = 60,
			/datum/affliction_symptom/cold_mottled_skin = 50,
		), 2, 3, list("factors" = alist(BF_SLOWDOWN = 0.45))),
	)
	return S
