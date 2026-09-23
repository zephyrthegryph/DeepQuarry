// Oxygenation, cardiac stabilisers and thermoregulation: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/chem_side_effect/dexalinp_dysphoria
	name = "dexalin-plus dysphoria"
	clinical_description = "Dexalin-plus carries an oxygenation-related stimulant rush. Some patients report mild confusion and dissociative effects while on therapeutic dose. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 70,
		/datum/affliction_symptom/dizziness = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_DEXALINP = 5)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/dexalin
	name = "dexalin overdose"
	clinical_description = "Excess dexalin disrupts normal oxygen exchange — paradoxically, too much makes breathing less effective."
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 80,
		/datum/affliction_symptom/confusion         = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_DEXALIN = 20)
	caused_by_chems_organ = O_LUNGS

/datum/affliction/overdose/dexalin/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/short_breath = 60), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/labored_breathing = 80,
			/datum/affliction_symptom/confusion         = 40,
		), 1, 2, list("factors" = alist(BF_O2_SAT = -8))),
		chem_stage(list(
			/datum/affliction_symptom/labored_breathing = 95,
			/datum/affliction_symptom/cyanosis          = 70,
			/datum/affliction_symptom/confusion         = 60,
		), 2, 3, list("factors" = alist(BF_O2_SAT = -15, BF_RESP_RATE = -4), "always_spawns" = list(/datum/affliction/respiratory_failure))),
	)
	return S

/datum/affliction/overdose/dexalinp
	name = "dexalin-plus overdose"
	clinical_description = "Dexalin-plus at overdose causes the same paradoxical oxygenation failure as dexalin, but at higher intensity, with confusion and motor symptoms."
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 90,
		/datum/affliction_symptom/confusion         = 70,
		/datum/affliction_symptom/unsteady_gait     = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_DEXALINP = 20)
	caused_by_chems_organ = O_LUNGS

/datum/affliction/overdose/dexalinp/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/short_breath = 70,
			/datum/affliction_symptom/dizziness    = 40,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/labored_breathing = 85,
			/datum/affliction_symptom/confusion         = 60,
			/datum/affliction_symptom/unsteady_gait     = 50,
		), 2, 3, list("factors" = alist(BF_O2_SAT = -10))),
		chem_stage(list(
			/datum/affliction_symptom/labored_breathing = 100,
			/datum/affliction_symptom/cyanosis          = 80,
			/datum/affliction_symptom/confusion         = 80,
			/datum/affliction_symptom/unsteady_gait     = 70,
		), 3, 4, list("factors" = alist(BF_O2_SAT = -20, BF_RESP_RATE = -5), "always_spawns" = list(/datum/affliction/respiratory_failure))),
	)
	return S

/datum/affliction/overdose/inaprovaline
	factors = alist(BF_HEART_RATE = -15, BF_BP_SYSTOLIC = -20)
	name = "inaprovaline overdose"
	clinical_description = "Excess inaprovaline depresses cardiac output. Hypotension, bradycardia, and reduced respiratory drive."
	symptom_pool = list(
		/datum/affliction_symptom/pallor        = 70,
		/datum/affliction_symptom/short_breath  = 60,
		/datum/affliction_symptom/drowsy        = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_INAPROVALINE = 60)
	caused_by_chems_organ = O_HEART

/datum/affliction/overdose/inaprovaline/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/drowsy = 60,
			/datum/affliction_symptom/pallor = 50,
		), 1, 2, list("factors" = alist(BF_HEART_RATE = -5, BF_BP_SYSTOLIC = -8))),
		chem_stage(list(
			/datum/affliction_symptom/pallor       = 75,
			/datum/affliction_symptom/short_breath = 60,
			/datum/affliction_symptom/drowsy       = 60,
		), 2, 3, list("factors" = alist(BF_HEART_RATE = -12, BF_BP_SYSTOLIC = -15))),
		chem_stage(list(
			/datum/affliction_symptom/pallor            = 90,
			/datum/affliction_symptom/labored_breathing = 80,
			/datum/affliction_symptom/drowsy            = 80,
			/datum/affliction_symptom/cold_mottled_skin = 50,
		), 3, 4, list("factors" = alist(BF_HEART_RATE = -22, BF_BP_SYSTOLIC = -28, BF_RESP_RATE = -3), "always_spawns" = list(/datum/affliction/hypovolemic_shock))),
	)
	return S

/datum/affliction/overdose/norepinephrine
	factors = alist(BF_HEART_RATE = 30, BF_BP_SYSTOLIC = 35, BF_BP_DIASTOLIC = 20)
	name = "norepinephrine overdose"
	clinical_description = "Too much vasopressor clamps the vessels down hard: severe hypertension, a racing heart, cold pale extremities and a pounding headache. Stop the infusion; it clears as the drug metabolises."
	symptom_pool = list(
		/datum/affliction_symptom/palpitations      = 80,
		/datum/affliction_symptom/headache          = 70,
		/datum/affliction_symptom/pallor            = 50,
		/datum/affliction_symptom/cold_mottled_skin = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_NOREPINEPHRINE = REAGENTS_OVERDOSE)
	caused_by_chems_organ = O_HEART

/datum/affliction/overdose/norepinephrine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/palpitations = 70,
			/datum/affliction_symptom/headache     = 60,
		), 1, 2, list("factors" = alist(BF_HEART_RATE = 10, BF_BP_SYSTOLIC = 12))),
		chem_stage(list(
			/datum/affliction_symptom/palpitations = 80,
			/datum/affliction_symptom/headache     = 70,
			/datum/affliction_symptom/pallor       = 50,
		), 2, 3, list("factors" = alist(BF_HEART_RATE = 22, BF_BP_SYSTOLIC = 25, BF_BP_DIASTOLIC = 12))),
		chem_stage(list(
			/datum/affliction_symptom/palpitations      = 90,
			/datum/affliction_symptom/headache          = 80,
			/datum/affliction_symptom/pallor            = 70,
			/datum/affliction_symptom/cold_mottled_skin = 60,
		), 3, 4, list("factors" = alist(BF_HEART_RATE = 35, BF_BP_SYSTOLIC = 40, BF_BP_DIASTOLIC = 22))),
	)
	return S

/datum/affliction/overdose/leporazine
	name = "leporazine overdose"
	clinical_description = "Leporazine overdose causes thermoregulatory chaos — the patient's temperature swings unpredictably, accompanied by chills and sweats."
	symptom_pool = list(
		/datum/affliction_symptom/chills            = 70,
		/datum/affliction_symptom/fever_sensation   = 60,
		/datum/affliction_symptom/fatigue           = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_LEPORAZINE = 20)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/overdose/leporazine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/chills          = 55,
			/datum/affliction_symptom/fever_sensation = 45,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/chills          = 75,
			/datum/affliction_symptom/fever_sensation = 65,
			/datum/affliction_symptom/fatigue         = 50,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/chills            = 90,
			/datum/affliction_symptom/fever_sensation   = 85,
			/datum/affliction_symptom/fatigue           = 70,
			/datum/affliction_symptom/cold_mottled_skin = 55,
		), 3, 4, list("always_spawns" = list(/datum/affliction/heatstroke, /datum/affliction/hypothermia))),
	)
	return S
