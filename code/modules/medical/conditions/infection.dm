// Infection cascade chain.
//
// wound_infection → cellulitis → sepsis → septic_shock → cardiac_arrest
//
// Spaceacillin is the universal cure but the further down the chain,
// the harder it gets to push severity back down. Septic shock is
// nearly terminal and only modern care + active antibiotics + fluids
// can pull a patient back.
//
// Each link presents differently:
//   cellulitis    — local: swelling, throbbing, fever
//   sepsis        — systemic: confusion, tachycardia, fever
//   septic_shock  — circulatory collapse: pallor, low BP, weakness

/datum/medical_issue/condition/cellulitis
	name = "cellulitis"
	category = "Infection"
	clinical_description = "Bacterial infection spreading through soft tissue. The site grows hot, red, and tender."
	progression_rate = 0.5
	// Spaceacillin is the standard narrow-spectrum antibiotic;
	// corophizine is the wide-spectrum alternative (faster but causes
	// GI side effects). Either works; their combo has a documented
	// interference, see chem_effects.dm.
	cured_by = list(REAGENT_ID_SPACEACILLIN = 1.2, REAGENT_ID_COROPHIZINE = 1.5)
	symptom_pool = list(
		/datum/medical_symptom/throbbing_pain  = 80,
		/datum/medical_symptom/fever_sensation = 70,
		/datum/medical_symptom/chills          = 50,
		/datum/medical_symptom/fatigue         = 60,
	)
	min_symptoms = 1
	max_symptoms = 3
	// Pulse derives from body state; tachycardia comes from raised
	// body temp (handled in tick_condition below). We only need to
	// fudge temp readings if we want a discrepancy between actual and
	// reading — leave readings linked to truth.
	mechanical_effects = list(
		"slowdown" = 0.3,
		"spontaneous_emotes" = list("wince", "shudder"),
		"spontaneous_emote_prob" = 3,
	)

// Push actual body temperature up while present. Upstream
// stabilize_body_temperature pulls it back toward normal each tick, so
// we keep nudging.
/datum/medical_issue/condition/cellulitis/tick_condition()
	. = ..()
	if(severity <= 0 || !owner)
		return
	// Up to about +2°C at severity 100. Body's regulation will fight
	// back, so we apply repeatedly. Scale by severity so a low-grade
	// fever feels different from a high one.
	var/target_offset_k = (severity / 100) * 2.0
	owner.bodytemperature = min(owner.bodytemperature + target_offset_k * 0.1, 310.15 + 2.5)  // 310.15K = 37C

/datum/medical_issue/condition/sepsis
	name = "sepsis"
	category = "Infection"
	clinical_description = "A systemic inflammatory response to bacterial invasion of the bloodstream. The whole body is fighting, and losing."
	progression_rate = 0.7
	// Sepsis needs aggressive antibiotic coverage: corophizine's wide
	// spectrum + spaceacillin together. Inaprovaline supports BP.
	cured_by = list(REAGENT_ID_COROPHIZINE = 1.4, REAGENT_ID_SPACEACILLIN = 1.0, REAGENT_ID_INAPROVALINE = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/fever_sensation = 80,
		/datum/medical_symptom/chills          = 70,
		/datum/medical_symptom/confusion       = 50,
		/datum/medical_symptom/pallor          = 50,
		/datum/medical_symptom/fatigue         = 60,
		/datum/medical_symptom/short_breath    = 40,
	)
	min_symptoms = 2
	max_symptoms = 4
	// Pulse derives from elevated body temp; BP drop from vasodilation
	// is real and the only thing not modelled elsewhere.
	mechanical_effects = list(
		"slowdown" = 0.6,
		"accuracy_penalty" = 10,
		"spontaneous_emotes" = list("shudder", "cough", "groan"),
		"spontaneous_emote_prob" = 4,
	)
	// Sepsis is multi-organ inflammation; the kidneys take the first hit.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 1
	organ_damage_targets = list(O_KIDNEYS)

// Bigger fever push than cellulitis — systemic.
/datum/medical_issue/condition/sepsis/tick_condition()
	. = ..()
	if(severity <= 0 || !owner)
		return
	var/target_offset_k = (severity / 100) * 3.5
	owner.bodytemperature = min(owner.bodytemperature + target_offset_k * 0.1, 310.15 + 4.0)

/datum/medical_issue/condition/septic_shock
	name = "septic shock"
	category = "Infection"
	clinical_description = "Sepsis past the point of compensation: blood pressure collapses and organs begin to fail."
	progression_rate = 1.0
	// Late-stage sepsis needs the strongest antibiotic + BP support +
	// red-cell support to drag the patient back.
	cured_by = list(REAGENT_ID_COROPHIZINE = 1.0, REAGENT_ID_SPACEACILLIN = 0.6, REAGENT_ID_INAPROVALINE = 0.5, REAGENT_ID_IRON = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/pallor          = 90,
		/datum/medical_symptom/confusion       = 70,
		/datum/medical_symptom/dizziness       = 70,
		/datum/medical_symptom/short_breath    = 60,
		/datum/medical_symptom/chills          = 60,
	)
	min_symptoms = 2
	max_symptoms = 4
	// Temp pushed by actual bodytemperature mutation; BP collapse from
	// septic vasodilation is real and not otherwise modelled.
	mechanical_effects = list(
		"slowdown" = 1.5,
		"accuracy_penalty" = 25,
		"drop_held_prob" = 4,
		"spontaneous_emotes" = list("collapse", "shudder", "groan"),
		"spontaneous_emote_prob" = 6,
	)
	// Septic shock: multi-organ failure. Liver and kidneys go first;
	// when they're max-damaged the patient's reagent metabolism breaks
	// and oxyloss builds on top.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 4
	organ_damage_targets = list(O_LIVER, O_KIDNEYS)

/datum/medical_issue/condition/sepsis/get_vital_effects()
	var/static/list/L = list("bp_sys_mod" = -15)
	return L

/datum/medical_issue/condition/septic_shock/get_vital_effects()
	var/static/list/L = list(
		"bp_sys_mod" = -45,
		"bp_dia_mod" = -25,
		"o2_sat_mod" = -10,
	)
	return L
