// Antitoxins, radiation purgers, antacids and alcohol antagonists: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/chem_side_effect/antitoxin_nausea
	name = "antitoxin nausea"
	clinical_description = "Antitoxin scrubs toxins from the blood but the breakdown byproducts can churn the stomach. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/nausea = 80,
	)
	min_symptoms = 1
	max_symptoms = 1
	caused_by_chems = list(REAGENT_ID_ANTITOXIN = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/chem_side_effect/carthatoline_evacuant
	name = "carthatoline evacuation"
	clinical_description = "Carthatoline is a powerful gastrointestinal evacuant — it scrubs toxins out of the gut by force. The patient feels profoundly sick while it's working. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 95,
		/datum/affliction_symptom/pallor    = 60,
		/datum/affliction_symptom/fatigue   = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_CARTHATOLINE = 5)
	caused_by_chems_organ = O_LIVER

/datum/affliction/chem_side_effect/arithrazine_toxicity
	name = "arithrazine toxicity"
	clinical_description = "Arithrazine clears acute radiation aggressively but is harsh on the body's own tissues. Sustained high-dose use produces toxin damage. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/fatigue   = 60,
		/datum/affliction_symptom/jaundice  = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	// Stacks toxin injury while present — the chem really is harming the
	// patient even as it clears radiation.
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 0.6
	caused_by_chems = list(REAGENT_ID_ARITHRAZINE = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/antitoxin
	name = "antitoxin overdose"
	clinical_description = "Antitoxin at overdose disrupts the body's normal electrolyte balance. Patients become weak, nauseated, and disoriented."
	symptom_pool = list(
		/datum/affliction_symptom/nausea     = 70,
		/datum/affliction_symptom/fatigue    = 80,
		/datum/affliction_symptom/confusion  = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_ANTITOXIN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/antitoxin/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/nausea  = 60,
			/datum/affliction_symptom/fatigue = 60,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/nausea    = 75,
			/datum/affliction_symptom/fatigue   = 80,
			/datum/affliction_symptom/confusion = 40,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/nausea        = 90,
			/datum/affliction_symptom/fatigue       = 95,
			/datum/affliction_symptom/confusion     = 65,
			/datum/affliction_symptom/limb_weakness = 50,
		), 3, 4, list("always_spawns" = list(/datum/affliction/toxic_poisoning))),
	)
	return S

/datum/affliction/overdose/carthatoline
	name = "carthatoline overdose"
	clinical_description = "Carthatoline at overdose strips the patient's electrolytes alongside the toxins it's meant to clear. Dehydration, weakness, and ongoing GI distress."
	symptom_pool = list(
		/datum/affliction_symptom/nausea     = 95,
		/datum/affliction_symptom/pallor     = 80,
		/datum/affliction_symptom/fatigue    = 70,
		/datum/affliction_symptom/dizziness  = 50,
	)
	min_symptoms = 2
	max_symptoms = 4
	caused_by_chems = list(REAGENT_ID_CARTHATOLINE = 15)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/carthatoline/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/nausea  = 75,
			/datum/affliction_symptom/fatigue = 55,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/nausea    = 90,
			/datum/affliction_symptom/pallor    = 75,
			/datum/affliction_symptom/fatigue   = 70,
			/datum/affliction_symptom/dizziness = 50,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/nausea            = 100,
			/datum/affliction_symptom/pallor            = 95,
			/datum/affliction_symptom/fatigue           = 90,
			/datum/affliction_symptom/dizziness         = 75,
			/datum/affliction_symptom/cold_mottled_skin = 50,
		), 3, 4),
	)
	return S

/datum/affliction/overdose/hyronalin
	name = "hyronalin overdose"
	clinical_description = "Hyronalin overdose stresses the same tissues it's meant to protect — patients feel weak and queasy."
	symptom_pool = list(
		/datum/affliction_symptom/fatigue = 70,
		/datum/affliction_symptom/nausea  = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_HYRONALIN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/hyronalin/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/fatigue = 55,
			/datum/affliction_symptom/nausea  = 45,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/fatigue = 75,
			/datum/affliction_symptom/nausea  = 60,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/fatigue           = 90,
			/datum/affliction_symptom/nausea            = 80,
			/datum/affliction_symptom/radiation_reading = 50,
		), 2, 3, list("always_spawns" = list(/datum/affliction/acute_radiation))),
	)
	return S

/datum/affliction/overdose/arithrazine
	name = "arithrazine overdose"
	clinical_description = "Arithrazine at overdose is severely tissue-damaging — the same reactivity that scrubs radiation out of the cellular machinery turns indiscriminate. Persistent tox loading, weakness, and broad organ stress."
	symptom_pool = list(
		/datum/affliction_symptom/nausea     = 85,
		/datum/affliction_symptom/fatigue    = 70,
		/datum/affliction_symptom/jaundice   = 60,
		/datum/affliction_symptom/pallor     = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 1.0
	caused_by_chems = list(REAGENT_ID_ARITHRAZINE = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/arithrazine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/nausea  = 65,
			/datum/affliction_symptom/fatigue = 50,
		), 1, 2, list("organ_damage_per_tick" = 0.35, "organ_damage_type" = INJURY_TOXIN)),
		chem_stage(list(
			/datum/affliction_symptom/nausea   = 85,
			/datum/affliction_symptom/fatigue  = 70,
			/datum/affliction_symptom/jaundice = 55,
			/datum/affliction_symptom/pallor   = 40,
		), 2, 3, list("organ_damage_per_tick" = 0.7, "organ_damage_type" = INJURY_TOXIN)),
		chem_stage(list(
			/datum/affliction_symptom/nausea            = 100,
			/datum/affliction_symptom/fatigue           = 90,
			/datum/affliction_symptom/jaundice          = 80,
			/datum/affliction_symptom/pallor            = 70,
			/datum/affliction_symptom/radiation_reading = 50,
		), 3, 4, list("organ_damage_per_tick" = 1.3, "organ_damage_type" = INJURY_TOXIN)),
	)
	return S

/datum/affliction/overdose/calciumcarbonate
	name = "calcium carbonate overdose"
	clinical_description = "Excess calcium carbonate overwhelms the gut — chalky residue irritates the stomach lining, throws off electrolytes, and the kidneys strain to clear the load. Nausea and abdominal tenderness predominate."
	symptom_pool = list(
		/datum/affliction_symptom/nausea                = 85,
		/datum/affliction_symptom/abdominal_tenderness  = 60,
		/datum/affliction_symptom/fatigue               = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_CALCIUMCARBONATE = 24)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/calciumcarbonate/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/nausea = 65), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/nausea               = 85,
			/datum/affliction_symptom/abdominal_tenderness = 60,
			/datum/affliction_symptom/fatigue              = 40,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/nausea               = 100,
			/datum/affliction_symptom/abdominal_tenderness = 85,
			/datum/affliction_symptom/fatigue              = 65,
			/datum/affliction_symptom/limb_weakness        = 55,
		), 3, 4),
	)
	return S

/datum/affliction/overdose/ethylredoxrazine
	name = "ethylredoxrazine overdose"
	clinical_description = "Ethylredoxrazine is a strong oxidiser — at overdose the same reactivity that scrubs ethanol turns on the body's own tissues. Liver irritation, nausea, and a general oxidative stress that wears the patient down."
	symptom_pool = list(
		/datum/affliction_symptom/nausea   = 75,
		/datum/affliction_symptom/jaundice = 50,
		/datum/affliction_symptom/fatigue  = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.3
	organ_damage_targets = list(O_LIVER)
	caused_by_chems = list(REAGENT_ID_ETHYLREDOXRAZINE = 30)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/ethylredoxrazine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/nausea = 60), 1, 1, list("organ_damage_per_tick" = 0.1, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
		chem_stage(list(
			/datum/affliction_symptom/nausea   = 75,
			/datum/affliction_symptom/jaundice = 50,
			/datum/affliction_symptom/fatigue  = 50,
		), 1, 2, list("organ_damage_per_tick" = 0.25, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
		chem_stage(list(
			/datum/affliction_symptom/nausea               = 90,
			/datum/affliction_symptom/jaundice             = 75,
			/datum/affliction_symptom/fatigue              = 75,
			/datum/affliction_symptom/abdominal_tenderness = 55,
		), 2, 3, list("organ_damage_per_tick" = 0.45, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
	)
	return S
