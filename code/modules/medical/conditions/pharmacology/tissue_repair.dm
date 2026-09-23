// Brute and burn repair, stabilisers and hemostatics: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/overdose/bicaridine
	name = "bicaridine overdose"
	clinical_description = "Bicaridine at overdose interferes with normal clotting — the patient becomes prone to spontaneous bleeding. The same antiplatelet activity also drains intracranial bleeding faster than any other chem can; a bicaridine OD will resolve a subdural hematoma when no surgeon is available, at the cost of broad external bleeding."
	symptom_pool = list(
		/datum/affliction_symptom/bleeding_visible = 80,
		/datum/affliction_symptom/pallor           = 60,
	)
	min_symptoms = 1
	max_symptoms = 2
	od_cures_externally = list(/datum/affliction/subdural_hematoma = 0.8)
	caused_by_chems = list(REAGENT_ID_BICARIDINE = 20)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/overdose/bicaridine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/pallor = 60), 0, 1),
		chem_stage(list(
			/datum/affliction_symptom/bleeding_visible = 80,
			/datum/affliction_symptom/pallor           = 60,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/bleeding_visible = 100,
			/datum/affliction_symptom/pallor           = 80,
			/datum/affliction_symptom/dizziness        = 60,
		), 2, 3, list("always_spawns" = list(/datum/affliction/internal_hemorrhage))),
	)
	return S

/datum/affliction/overdose/bicaridaze
	name = "bicaridaze overdose"
	clinical_description = "Bicaridaze is a topical bicaridine that's absorbed slowly through the skin. At overdose the same antiplatelet effect as bicaridine itself surfaces — bleeding becomes harder to control — with the added burden of cumulative skin/dermal irritation from the carrier."
	symptom_pool = list(
		/datum/affliction_symptom/bleeding_visible  = 70,
		/datum/affliction_symptom/pallor            = 60,
		/datum/affliction_symptom/skin_burns_minor  = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_BICARIDAZE = 22)
	caused_by_chems_organ = BP_TORSO

/datum/affliction/overdose/bicaridaze/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/pallor           = 50,
			/datum/affliction_symptom/skin_burns_minor = 40,
		), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/bleeding_visible = 70,
			/datum/affliction_symptom/pallor           = 60,
			/datum/affliction_symptom/skin_burns_minor = 50,
		), 2, 2),
		chem_stage(list(
			/datum/affliction_symptom/bleeding_visible = 90,
			/datum/affliction_symptom/pallor           = 80,
			/datum/affliction_symptom/skin_burns_minor = 70,
			/datum/affliction_symptom/dizziness        = 60,
		), 3, 4),
	)
	return S

/datum/affliction/overdose/kelotane
	name = "kelotane overdose"
	clinical_description = "Excess kelotane irritates the digestive tract. Nausea and tissue inflammation as the drug overwhelms the body's normal burn-response pathway."
	symptom_pool = list(
		/datum/affliction_symptom/nausea  = 70,
		/datum/affliction_symptom/pallor  = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_KELOTANE = 20)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/kelotane/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(/datum/affliction_symptom/nausea = 60), 1, 1),
		chem_stage(list(
			/datum/affliction_symptom/nausea = 75,
			/datum/affliction_symptom/pallor = 50,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/nausea           = 90,
			/datum/affliction_symptom/pallor           = 75,
			/datum/affliction_symptom/skin_burns_minor = 50,
		), 2, 3),
	)
	return S

/datum/affliction/overdose/dermaline
	name = "dermaline overdose"
	clinical_description = "Dermaline's potency makes its overdose harsher than kelotane's. Severe nausea, vascular dilation, and broad tissue irritation."
	symptom_pool = list(
		/datum/affliction_symptom/nausea   = 80,
		/datum/affliction_symptom/pallor   = 60,
		/datum/affliction_symptom/dizziness = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_DERMALINE = 15)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/dermaline/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/nausea = 65,
			/datum/affliction_symptom/pallor = 45,
		), 1, 2),
		chem_stage(list(
			/datum/affliction_symptom/nausea    = 80,
			/datum/affliction_symptom/pallor    = 65,
			/datum/affliction_symptom/dizziness = 50,
		), 2, 3),
		chem_stage(list(
			/datum/affliction_symptom/nausea           = 95,
			/datum/affliction_symptom/pallor           = 85,
			/datum/affliction_symptom/dizziness        = 70,
			/datum/affliction_symptom/skin_burns_minor = 60,
		), 3, 4),
	)
	return S

/datum/affliction/overdose/tricordrazine
	name = "tricordrazine overdose"
	clinical_description = "Tricordrazine overdose is severely toxic — the broad-spectrum stabiliser becomes a broad-spectrum harm. Multi-system distress, liver damage, and weakness."
	symptom_pool = list(
		/datum/affliction_symptom/fatigue   = 90,
		/datum/affliction_symptom/nausea    = 70,
		/datum/affliction_symptom/jaundice  = 60,
		/datum/affliction_symptom/pallor    = 50,
	)
	min_symptoms = 2
	max_symptoms = 4
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.6
	organ_damage_targets = list(O_LIVER)
	caused_by_chems = list(REAGENT_ID_TRICORDRAZINE = 120)
	caused_by_chems_organ = O_LIVER

/datum/affliction/overdose/tricordrazine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/fatigue = 70,
			/datum/affliction_symptom/nausea  = 55,
		), 1, 2, list("organ_damage_per_tick" = 0.2, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
		chem_stage(list(
			/datum/affliction_symptom/fatigue  = 85,
			/datum/affliction_symptom/nausea   = 70,
			/datum/affliction_symptom/jaundice = 55,
			/datum/affliction_symptom/pallor   = 50,
		), 2, 3, list("organ_damage_per_tick" = 0.45, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
		chem_stage(list(
			/datum/affliction_symptom/fatigue              = 100,
			/datum/affliction_symptom/nausea               = 90,
			/datum/affliction_symptom/jaundice             = 80,
			/datum/affliction_symptom/pallor               = 75,
			/datum/affliction_symptom/abdominal_tenderness = 60,
		), 3, 4, list("organ_damage_per_tick" = 0.9, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_LIVER))),
	)
	return S

/datum/affliction/overdose/myelamine
	name = "myelamine overdose"
	clinical_description = "Myelamine at overdose drives clotting past the point of utility — platelets aggregate in the small vessels, creating microthrombi while the liver works overtime clearing the breakdown products. Chest pain, fatigue, and accumulating toxin damage."
	symptom_pool = list(
		/datum/affliction_symptom/sharp_chest_pain = 70,
		/datum/affliction_symptom/fatigue          = 60,
		/datum/affliction_symptom/palpitations     = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = INJURY_TOXIN
	organ_damage_per_tick = 0.6
	caused_by_chems = list(REAGENT_ID_MYELAMINE = 15)
	caused_by_chems_organ = O_HEART

/datum/affliction/overdose/myelamine/get_stages()
	var/static/list/S = overdose_stages(
		chem_stage(list(
			/datum/affliction_symptom/fatigue      = 55,
			/datum/affliction_symptom/palpitations = 40,
		), 1, 1, list("organ_damage_per_tick" = 0.2, "organ_damage_type" = INJURY_TOXIN)),
		chem_stage(list(
			/datum/affliction_symptom/sharp_chest_pain = 70,
			/datum/affliction_symptom/fatigue          = 60,
			/datum/affliction_symptom/palpitations     = 50,
		), 2, 3, list("organ_damage_per_tick" = 0.4, "organ_damage_type" = INJURY_TOXIN)),
		chem_stage(list(
			/datum/affliction_symptom/sharp_chest_pain    = 90,
			/datum/affliction_symptom/fatigue             = 80,
			/datum/affliction_symptom/palpitations        = 75,
			/datum/affliction_symptom/chest_pain_crushing = 50,
		), 3, 4, list("organ_damage_per_tick" = 0.85, "organ_damage_type" = INJURY_TOXIN)),
	)
	return S
