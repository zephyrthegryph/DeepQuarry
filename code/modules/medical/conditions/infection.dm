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

/datum/affliction/cellulitis
	name = "cellulitis"
	category = "Infection"
	clinical_description = "Bacterial infection spreading through soft tissue. The site grows hot, red, and tender."
	progression_rate = 0.5
	// Spaceacillin is the standard narrow-spectrum antibiotic;
	// corophizine is the wide-spectrum alternative (faster but causes
	// GI side effects). Either works; their combo has a documented
	// interference, see the chemical side-effect conditions.
	treated_by = list(TREAT_ANTIMICROBIAL = 1.2, TREAT_RESECTION = 1)
	symptom_pool = list(
		/datum/affliction_symptom/throbbing_pain  = 80,
		/datum/affliction_symptom/fever_sensation = 70,
		/datum/affliction_symptom/chills          = 50,
		/datum/affliction_symptom/fatigue         = 60,
	)
	min_symptoms = 1
	max_symptoms = 3
	// Pulse derives from body state; tachycardia comes from raised
	// body temp (handled in tick below). We only need to
	// fudge temp readings if we want a discrepancy between actual and
	// reading — leave readings linked to truth.
	factors = alist(BF_SLOWDOWN = 0.3)
	spontaneous_emotes = list("wince", "shudder")
	spontaneous_emote_prob = 3

// Push actual body temperature up while present. Upstream
// stabilize_body_temperature pulls it back toward normal each tick, so
// we keep nudging.
/datum/affliction/cellulitis/tick()
	. = ..()
	if(severity <= 0 || !owner)
		return
	// Up to about +2°C at severity 100. Body's regulation will fight
	// back, so we apply repeatedly. Scale by severity so a low-grade
	// fever feels different from a high one.
	var/target_offset_k = (severity / 100) * 2.0
	owner.bodytemperature = min(owner.bodytemperature + target_offset_k * 0.1, BODYTEMP_NORMAL + 2.5)

/datum/affliction/sepsis
	name = "sepsis"
	category = "Infection"
	clinical_description = "A systemic inflammatory response to bacterial invasion of the bloodstream. The whole body is fighting, and losing."
	progression_rate = 0.7
	// Sepsis needs aggressive antibiotic coverage: corophizine's wide
	// spectrum + spaceacillin together. Inaprovaline supports BP.
	treated_by = list(TREAT_ANTIMICROBIAL = 1.05, TREAT_CIRCULATORY = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 80,
		/datum/affliction_symptom/chills          = 70,
		/datum/affliction_symptom/confusion       = 50,
		/datum/affliction_symptom/pallor          = 50,
		/datum/affliction_symptom/fatigue         = 60,
		/datum/affliction_symptom/short_breath    = 40,
	)
	min_symptoms = 2
	max_symptoms = 4
	// Pulse derives from elevated body temp; BP drop from vasodilation
	// is real and the only thing not modelled elsewhere.
	factors = alist(BF_SLOWDOWN = 0.6, BF_ACCURACY = -10, BF_BP_SYSTOLIC = -15)
	spontaneous_emotes = list("shudder", "cough", "groan")
	spontaneous_emote_prob = 4
	// Sepsis is multi-organ inflammation; the kidneys take the first hit.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 1
	organ_damage_targets = list(O_KIDNEYS)

// Bigger fever push than cellulitis — systemic.
/datum/affliction/sepsis/tick()
	. = ..()
	if(severity <= 0 || !owner)
		return
	var/target_offset_k = (severity / 100) * 3.5
	owner.bodytemperature = min(owner.bodytemperature + target_offset_k * 0.1, BODYTEMP_NORMAL + 4.0)

/datum/affliction/septic_shock
	name = "septic shock"
	category = "Infection"
	clinical_description = "Sepsis past the point of compensation: blood pressure collapses and organs begin to fail."
	progression_rate = 1.0
	// Late-stage sepsis needs the strongest antibiotic + BP support +
	// red-cell support to drag the patient back.
	treated_by = list(TREAT_ANTIMICROBIAL = 0.75, TREAT_CIRCULATORY = 0.5, TREAT_BLOOD_RESTORE = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/pallor          = 90,
		/datum/affliction_symptom/confusion       = 70,
		/datum/affliction_symptom/dizziness       = 70,
		/datum/affliction_symptom/short_breath    = 60,
		/datum/affliction_symptom/chills          = 60,
	)
	min_symptoms = 2
	max_symptoms = 4
	// Temp pushed by actual bodytemperature mutation; BP collapse from
	// septic vasodilation is real and not otherwise modelled.
	factors = alist(BF_SLOWDOWN = 1.5, BF_ACCURACY = -25, BF_MOTOR_CONTROL = 0.96, BF_BP_SYSTOLIC = -45, BF_BP_DIASTOLIC = -25, BF_O2_SAT = -10)
	spontaneous_emotes = list("collapse", "shudder", "groan")
	spontaneous_emote_prob = 6
	// Septic shock: multi-organ failure. Liver and kidneys go first;
	// when they're max-damaged the patient's reagent metabolism breaks
	// and hypoxia builds on top.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 4
	organ_damage_targets = list(O_LIVER, O_KIDNEYS)

