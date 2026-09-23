// Organ repair: the daxon family, eye drugs and cellular repair: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/overdose/peridaxon
	name = "peridaxon overdose"
	clinical_description = "Peridaxon at overdose induces hallucinations and disorientation — the same organ-receptor priming that makes it useful at therapeutic dose becomes overwhelming at high concentrations."
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 85,
		/datum/affliction_symptom/jittery   = 60,
		/datum/affliction_symptom/headache  = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_PERIDAXON = 10)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/peridaxon/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/jittery = 60), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/confusion = 70,
			/datum/affliction_symptom/jittery   = 50,
			/datum/affliction_symptom/headache  = 40,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/confusion = 95,
			/datum/affliction_symptom/jittery   = 80,
			/datum/affliction_symptom/headache  = 60,
		), 2, 3),
	)
	return S

/datum/affliction/overdose/imidazoline
	name = "imidazoline overdose"
	clinical_description = "Imidazoline at overdose paradoxically blurs vision and irritates the retina — too much of the receptor agonist overwhelms the normal signal."
	symptom_pool = list(
		/datum/affliction_symptom/blurred_vision = 80,
		/datum/affliction_symptom/cloudy_eye     = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_IMIDAZOLINE = 20)
	caused_by_chems_organ = O_EYES

/datum/affliction/overdose/imidazoline/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/blurred_vision = 55,
			/datum/affliction_symptom/cloudy_eye     = 40,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/blurred_vision = 80,
			/datum/affliction_symptom/cloudy_eye     = 50,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/blurred_vision      = 95,
			/datum/affliction_symptom/cloudy_eye          = 80,
			/datum/affliction_symptom/pupillary_asymmetry = 60,
		), 2, 3),
	)
	return S

/datum/affliction/overdose/osteodaxon
	name = "osteodaxon overdose"
	clinical_description = "Excess osteodaxon causes calcium dysregulation — muscle cramps, weakness, and bone pain visible as unsteadiness."
	symptom_pool = list(
		/datum/affliction_symptom/throbbing_pain  = 70,
		/datum/affliction_symptom/fatigue         = 60,
		/datum/affliction_symptom/unsteady_gait   = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_OSTEODAXON = 15)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/overdose/osteodaxon/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/throbbing_pain = 55,
			/datum/affliction_symptom/fatigue        = 45,
			/datum/affliction_symptom/unsteady_gait  = 35,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/throbbing_pain = 75,
			/datum/affliction_symptom/fatigue        = 65,
			/datum/affliction_symptom/unsteady_gait  = 50,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/throbbing_pain = 90,
			/datum/affliction_symptom/fatigue        = 85,
			/datum/affliction_symptom/unsteady_gait  = 75,
			/datum/affliction_symptom/limb_weakness  = 50,
		), 2, 3),
	)
	return S

/datum/affliction/overdose/respirodaxon
	name = "respirodaxon overdose"
	clinical_description = "Respirodaxon overdose over-proliferates lung tissue, paradoxically reducing gas exchange efficiency."
	symptom_pool = list(
		/datum/affliction_symptom/labored_breathing = 80,
		/datum/affliction_symptom/wet_cough         = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_RESPIRODAXON = 10)
	caused_by_chems_organ = O_LUNGS

/datum/affliction/overdose/respirodaxon/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/wet_cough    = 60,
			/datum/affliction_symptom/short_breath = 50,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/labored_breathing = 75,
			/datum/affliction_symptom/wet_cough         = 60,
		), 1, 2, list("factors" = alist(BF_O2_SAT = -6))),
		chem_stage(list(
			/datum/affliction_symptom/labored_breathing = 95,
			/datum/affliction_symptom/wet_cough         = 80,
			/datum/affliction_symptom/cyanosis          = 60,
		), 2, 3, list("factors" = alist(BF_O2_SAT = -14, BF_RESP_RATE = -4), "always_spawns" = list(/datum/affliction/respiratory_failure))),
	)
	return S

/datum/affliction/overdose/cordradaxon
	name = "cordradaxon overdose"
	clinical_description = "Cordradaxon overdose drives over-proliferation of cardiac tissue receptors — palpitations, chest discomfort, irregular rhythm. At peak severity the same receptor flood pulls a patient out of cardiac arrest at speeds open surgery would envy; the arrhythmia is the price."
	symptom_pool = list(
		/datum/affliction_symptom/palpitations     = 90,
		/datum/affliction_symptom/sharp_chest_pain = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	od_cures_externally = list(/datum/affliction/heart_damage = 1.2)
	caused_by_chems = list(REAGENT_ID_CORDRADAXON = 10)
	caused_by_chems_organ = O_HEART

/datum/affliction/overdose/cordradaxon/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/palpitations = 60), 0, 1, list("factors" = alist(BF_HEART_RATE = 10))),
		chem_stage(list(
			/datum/affliction_symptom/palpitations     = 85,
			/datum/affliction_symptom/sharp_chest_pain = 50,
		), 1, 2, list("factors" = alist(BF_HEART_RATE = 20))),
		chem_stage(list(
			/datum/affliction_symptom/palpitations        = 100,
			/datum/affliction_symptom/sharp_chest_pain    = 80,
			/datum/affliction_symptom/chest_pain_crushing = 50,
		), 2, 3, list("factors" = alist(BF_HEART_RATE = 35), "always_spawns" = list(/datum/affliction/chem_interaction/tachycardia_chem))),
	)
	return S

/datum/affliction/overdose/hepanephrodaxon
	name = "hepanephrodaxon overdose"
	clinical_description = "Hepanephrodaxon overdose strains the very organs it normally repairs — the chem overwhelms hepatic/renal receptors and produces metabolic upset."
	symptom_pool = list(
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/fatigue   = 70,
		/datum/affliction_symptom/jaundice  = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_HEPANEPHRODAXON = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/hepanephrodaxon/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/nausea  = 55,
			/datum/affliction_symptom/fatigue = 50,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/nausea   = 75,
			/datum/affliction_symptom/fatigue  = 70,
			/datum/affliction_symptom/jaundice = 40,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/nausea               = 90,
			/datum/affliction_symptom/fatigue              = 90,
			/datum/affliction_symptom/jaundice             = 75,
			/datum/affliction_symptom/abdominal_tenderness = 55,
		), 3, 4),
	)
	return S

/datum/affliction/overdose/gastirodaxon
	name = "gastirodaxon overdose"
	clinical_description = "Gastirodaxon overdose causes inflammatory GI cramping and impaired absorption."
	symptom_pool = list(
		/datum/affliction_symptom/nausea           = 80,
		/datum/affliction_symptom/throbbing_pain   = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_GASTIRODAXON = 10)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/gastirodaxon/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/nausea = 60), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/nausea         = 80,
			/datum/affliction_symptom/throbbing_pain = 55,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/nausea               = 95,
			/datum/affliction_symptom/throbbing_pain       = 80,
			/datum/affliction_symptom/abdominal_tenderness = 65,
		), 2, 3),
	)
	return S

/datum/affliction/overdose/rezadone
	name = "rezadone overdose"
	clinical_description = "Rezadone at overdose causes uncontrolled cellular replication — disorientation, weakness, and minor toxic effects as the body struggles to keep up."
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 60,
		/datum/affliction_symptom/fatigue   = 70,
		/datum/affliction_symptom/nausea    = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_REZADONE = 20)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/overdose/rezadone/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/fatigue = 55,
			/datum/affliction_symptom/nausea  = 40,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/confusion = 60,
			/datum/affliction_symptom/fatigue   = 70,
			/datum/affliction_symptom/nausea    = 50,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/confusion           = 80,
			/datum/affliction_symptom/fatigue             = 85,
			/datum/affliction_symptom/nausea              = 70,
			/datum/affliction_symptom/genetic_instability = 60,
		), 2, 3, list("always_spawns" = list(/datum/affliction/genetic_damage))),
	)
	return S

/datum/affliction/overdose/ryetalyn
	name = "ryetalyn overdose"
	clinical_description = "Ryetalyn at overdose interferes with normal cellular processes outside the genetic targets it's meant to fix. Weakness and mild GI symptoms."
	symptom_pool = list(
		/datum/affliction_symptom/fatigue = 70,
		/datum/affliction_symptom/nausea  = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_RYETALYN = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/ryetalyn/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/fatigue = 55,
			/datum/affliction_symptom/nausea  = 40,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/fatigue = 75,
			/datum/affliction_symptom/nausea  = 50,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/fatigue             = 90,
			/datum/affliction_symptom/nausea              = 70,
			/datum/affliction_symptom/genetic_instability = 60,
		), 2, 3, list("always_spawns" = list(/datum/affliction/genetic_damage))),
	)
	return S
