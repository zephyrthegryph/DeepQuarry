// Vital systems — Airway, Breathing, Circulation — as afflictions.
//
// The ABCs of resuscitation, each a root-cause affliction whose consequence is
// a body factor the physiology (code/modules/body/physiology.dm) reads. None of
// them harms the patient directly: the physiology turns lost ventilation or
// perfusion into oxygen debt, and the debt into hypoxia and brain lesions.
//
//   Airway      airway_obstruction  choking / aspirated vomit / facial trauma
//               airway_edema        allergy / inhalation burns
//               BF_AIRWAY falls with severity and closes (0) at the complete
//               threshold. Cure: TREAT_AIRWAY (Heimlich, airway kit),
//               TREAT_VASOPRESSOR (adrenaline / inaprovaline) for swelling.
//
//   Breathing   respiratory_arrest  opioid OD, brain herniation, deep hypoxia:
//                                   BF_RESP_DRIVE 0 while apneic. A bag-valve
//                                   mask or rescue breaths add a drive SUPPORT,
//                                   which can't push past a closed airway.
//               pneumothorax        air trapped in the chest (chest pierce, a
//                                   perforated lung): BF_LUNG_MECHANICS, and in
//                                   tension BF_PUMP too. TREAT_DECOMPRESSION
//                                   (needle, chest tube) vents it; a leaking lung
//                                   perforation re-fills it until surgery.
//
//   Circulation cardiac_arrhythmia  rhythm state machine:
//                                   sinus (settling) / tachy (perfusing, unstable)
//                                   / VF (no output, shockable) / asystole
//                                   (no output, NOT shockable). The rhythm's
//                                   stage sets BF_PUMP. CPR adds a BF_PUMP
//                                   support; TREAT_DEFIBRILLATION converts VF /
//                                   tachy only; TREAT_VASOPRESSOR coaxes asystole
//                                   back toward VF.
//
// Diagnosis is by symptom (singletons below, all SCANNER-visible) plus the
// rhythm readout on the health analyser and vitals monitor
// (cardiac_rhythm_reading()).

// --- Tuning ------------------------------------------------------------------------
/// % per tick an untreated VF degenerates to asystole.
#define ARREST_VF_DECAY_CHANCE 2
/// % per tick, per vasopressor level, that asystole coarsens into VF.
#define ARREST_VASOPRESSOR_CONVERSION 20
/// Respiratory arrest severity at or above which the patient doesn't breathe.
#define RESP_ARREST_APNEA_THRESHOLD 40
/// Pneumothorax severity at which it becomes a tension pneumothorax.
#define PNEUMOTHORAX_TENSION_THRESHOLD 60


// --- Airway ---------------------------------------------------------------------------

/datum/affliction/airway
	name = "airway compromise"
	catalogued = FALSE
	category = "Airway"
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	/// Severity at which the airway is completely closed (no gas exchange).
	var/complete_threshold = 50
	/// Severity a freshly created instance starts at.
	var/initial_severity = 30

/datum/affliction/airway/on_added()
	. = ..()
	if(!severity)
		set_severity(initial_severity)

/// Is the airway closed right now?
/datum/affliction/airway/proc/blocks_airway()
	return severity >= complete_threshold

/// Fraction of the airway still open: narrows to half just short of the
/// complete threshold, then closes.
/datum/affliction/airway/proc/patency()
	if(blocks_airway())
		return 0
	return 1 - 0.5 * severity / complete_threshold

/// The airway's patency is a factor the physiology reads.
/datum/affliction/airway/accumulate_factors(list/acc)
	acc = ..()
	return body_factor_accumulate(acc, alist(BF_AIRWAY = patency()), 1)

/// Something lodged in the airway: food, vomit, blood, a broken jaw.
/datum/affliction/airway_obstruction
	parent_type = /datum/affliction/airway
	name = "airway obstruction"
	catalogued = TRUE
	clinical_description = "Something is lodged in the upper airway — food, aspirated vomit, blood or displaced tissue from facial trauma. A complete obstruction stops all gas exchange: the patient can't breathe, speak or cough. Abdominal thrusts (the Heimlich manoeuvre, help intent on the chest) or an airway kit clear it; a conscious patient may cough a partial one free."
	initial_severity = 60
	// Coughing slowly clears a partial obstruction.
	progression_rate = -0.4
	treated_by = list(TREAT_AIRWAY = 1.0)
	symptom_pool = list(
		/datum/affliction_symptom/choking   = 100,
		/datum/affliction_symptom/stridor   = 40,
		/datum/affliction_symptom/cyanosis  = 50,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_ACTION_BLOCKS = ACTION_BLOCK_SPEECH, BF_HEART_RATE = 15)
	spontaneous_emotes = list("cough", "gasp")
	spontaneous_emote_prob = 8

/// Swelling of the upper airway: anaphylaxis, inhalation burns.
/datum/affliction/airway_edema
	parent_type = /datum/affliction/airway
	name = "airway edema"
	catalogued = TRUE
	clinical_description = "The tissues of the throat and upper airway are swelling shut — an allergic reaction or an inhalation burn. Breathing grows noisy (stridor) and then stops altogether once the airway closes. A vasopressor (adrenaline; an AllergyPen's inaprovaline in a pinch) shrinks the swelling; an airway kit holds it open."
	complete_threshold = 70
	initial_severity = 30
	// Subsides slowly once the trigger stops; allergens and burns keep adding.
	progression_rate = -0.3
	treated_by = list(TREAT_VASOPRESSOR = 1.5, TREAT_AIRWAY = 0.6)
	symptom_pool = list(
		/datum/affliction_symptom/stridor         = 100,
		/datum/affliction_symptom/facial_swelling = 70,
		/datum/affliction_symptom/wheeze          = 40,
		/datum/affliction_symptom/cyanosis        = 30,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_HEART_RATE = 20, BF_BP_SYSTOLIC = -15)
	spontaneous_emotes = list("cough", "gasp")
	spontaneous_emote_prob = 5

// --- Breathing ---------------------------------------------------------------------------

/// The patient has stopped breathing on their own.
/datum/affliction/respiratory_arrest
	factors = alist(BF_HEART_RATE = 10)
	name = "respiratory arrest"
	category = "Respiratory"
	clinical_description = "The drive to breathe has failed — an opioid overdose, brain herniation or profound hypoxia. The heart may still beat, but no breaths are taken. Someone must breathe for the patient: a bag-valve mask, or rescue breaths during CPR. The drive returns once its cause is treated."
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	// The drive recovers on its own once nothing is suppressing it.
	progression_rate = -1
	// Ventilation doesn't cure: a bag-valve mask or rescue breaths support the
	// drive (a body support). Respiratory stimulants hasten recovery.
	treated_by = list(TREAT_STIMULANT = 0.4)
	symptom_pool = list(
		/datum/affliction_symptom/absent_breath_sounds = 100,
		/datum/affliction_symptom/cyanosis             = 70,
		/datum/affliction_symptom/agonal_gasping       = 40,
	)
	min_symptoms = 1
	max_symptoms = 3

/datum/affliction/respiratory_arrest/on_added()
	. = ..()
	if(!severity)
		set_severity(AFFLICTION_SEVERITY_TERMINAL)

/// Not breathing on their own right now.
/datum/affliction/respiratory_arrest/proc/is_apneic()
	return severity >= RESP_ARREST_APNEA_THRESHOLD

/// The drive to breathe is a factor the physiology reads: none while apneic.
/datum/affliction/respiratory_arrest/accumulate_factors(list/acc)
	acc = ..()
	return body_factor_accumulate(acc, alist(BF_RESP_DRIVE = (is_apneic() ? 0 : 1 - severity / AFFLICTION_SEVERITY_TERMINAL)), 1)

/// Is something still suppressing the drive to breathe?
/datum/affliction/respiratory_arrest/proc/is_sustained()
	if(!body)
		return FALSE
	if(body.has_affliction(/datum/affliction/overdose/oxycodone))
		return TRUE
	var/datum/affliction/brain_damage/brain = body.find_affliction(/datum/affliction/brain_damage)
	if(brain?.stage == "Critical")
		return TRUE
	var/datum/affliction/tissue_hypoxia/hypoxia = body.find_affliction(/datum/affliction/tissue_hypoxia)
	return hypoxia && hypoxia.severity >= 85

/datum/affliction/respiratory_arrest/tick()
	progression_rate = is_sustained() ? 0 : initial(progression_rate)
	..()


/// Air trapped in the pleural space, collapsing the lung.
/datum/affliction/pneumothorax
	name = "pneumothorax"
	category = "Chest"
	clinical_description = "Air has leaked into the chest cavity and is collapsing the lung. Left alone the pressure builds into a tension pneumothorax that crushes the heart's return and stops gas exchange. A decompression needle vents it in the field; a chest tube is definitive. If the lung itself is perforated, air keeps leaking back in until the hole is surgically repaired."
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	progression_rate = 1.0
	treated_by = list(TREAT_DECOMPRESSION = 1.0, TREAT_OCCLUSIVE_SEAL = 0.6, TREAT_OXYGENATION = 0.3)
	symptom_pool = list(
		/datum/affliction_symptom/diminished_breath_sounds = 100,
		/datum/affliction_symptom/labored_breathing        = 80,
		/datum/affliction_symptom/sharp_chest_pain         = 60,
	)
	min_symptoms = 1
	max_symptoms = 3
	// A tense chest crushes the lung.
	organ_damage_threshold = PNEUMOTHORAX_TENSION_THRESHOLD
	organ_damage_type = "internal"
	organ_damage_per_tick = 2
	organ_damage_targets = list(O_LUNGS)
	/// Vented at least once; without an ongoing leak it now resolves.
	var/decompressed = FALSE

/datum/affliction/pneumothorax/on_added()
	. = ..()
	if(!severity)
		set_severity(25)

/datum/affliction/pneumothorax/get_stages()
	var/static/list/S = list(
		"Simple" = list(
			"name" = "pneumothorax",
			"description" = "A partially collapsed lung. Breath sounds are quiet on the affected side.",
			"symptom_pool" = list(
				/datum/affliction_symptom/diminished_breath_sounds = 100,
				/datum/affliction_symptom/short_breath             = 70,
				/datum/affliction_symptom/sharp_chest_pain         = 60,
			),
			"min_symptoms" = 1,
			"max_symptoms" = 3,
			"factors" = alist(BF_SLOWDOWN = 0.5, BF_LUNG_MECHANICS = 0.7, BF_RESP_RATE = 6),
		),
		"Tension" = list(
			"name" = "tension pneumothorax",
			"description" = "Trapped air under pressure has shoved the trachea aside and is crushing the heart's venous return. Decompress now.",
			"symptom_pool" = list(
				/datum/affliction_symptom/diminished_breath_sounds = 100,
				/datum/affliction_symptom/tracheal_deviation       = 90,
				/datum/affliction_symptom/labored_breathing        = 90,
				/datum/affliction_symptom/cyanosis                 = 60,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 4,
			"factors" = alist(BF_SLOWDOWN = 1.5, BF_ACCURACY = -20, BF_HEART_RATE = 25, BF_BP_SYSTOLIC = -25, BF_RESP_RATE = 12, BF_LUNG_MECHANICS = 0.25, BF_PUMP = 0.6),
			"spontaneous_emotes" = list("gasp", "wince"),
			"spontaneous_emote_prob" = 6,
		),
	)
	return S

/datum/affliction/pneumothorax/recompute_stage_from_severity()
	_apply_stage(severity >= PNEUMOTHORAX_TENSION_THRESHOLD ? "Tension" : "Simple")

/// A perforated lung that isn't being held by treatment keeps leaking air.
/datum/affliction/pneumothorax/proc/leak_active()
	var/mob/living/carbon/human/H = owner
	if(!istype(H))
		return FALSE
	var/obj/item/organ/internal/lungs = H.internal_organs_by_name?[O_LUNGS]
	if(!lungs)
		return FALSE
	var/datum/affliction/lesion/perforation/P = lungs.find_lesion(/datum/affliction/lesion/perforation)
	return P && !P.is_stabilised()

/datum/affliction/pneumothorax/tick()
	if(leak_active())
		progression_rate = 1.5
	else
		progression_rate = decompressed ? -1.5 : initial(progression_rate)
	..()

/datum/affliction/pneumothorax/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(tag == TREAT_DECOMPRESSION)
		decompressed = TRUE
	return ..()


// --- Circulation ---------------------------------------------------------------------------

/// A disordered heart rhythm. The state machine lives in `rhythm`; severity is
/// electrical instability (pinned at 100 while the heart has no output).
/datum/affliction/cardiac_arrhythmia
	name = "cardiac arrhythmia"
	category = "Circulation"
	clinical_description = "The heart's electrical rhythm has broken down. A fast unstable rhythm still pumps but degenerates if untreated. Ventricular fibrillation (VF) and asystole pump nothing: the patient collapses, the brain starts dying within minutes, and only CPR buys time. A defibrillator converts VF but cannot restart a flatline — asystole needs CPR and a vasopressor (adrenaline) until it coarsens into a shockable rhythm."
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	// Set per rhythm by set_rhythm().
	progression_rate = 0
	treated_by = list(
		TREAT_CARDIAC = 1.0,
		TREAT_CIRCULATORY = 0.6,
		TREAT_DEFIBRILLATION = 1.0,
		TREAT_CHEST_COMPRESSION = 1.0,
	)
	worsened_by_tags = list(TREAT_STIMULANT = 0.8)
	min_symptoms = 1
	max_symptoms = 3
	/// CARDIAC_RHYTHM_*.
	var/rhythm = CARDIAC_RHYTHM_VF

/datum/affliction/cardiac_arrhythmia/on_added()
	. = ..()
	set_rhythm(rhythm)

/datum/affliction/cardiac_arrhythmia/get_stages()
	var/static/list/S = list(
		"Sinus" = list(
			"name" = "post-arrest rhythm",
			"description" = "The rhythm has been restored and is settling. Monitor; it resolves on its own.",
			"symptom_pool" = list(
				/datum/affliction_symptom/rhythm_finding/sinus = 100,
				/datum/affliction_symptom/palpitations         = 30,
			),
			"min_symptoms" = 1,
			"max_symptoms" = 2,
			"consciousness_at_max" = 0,
		),
		"Tachycardia" = list(
			"name" = "unstable tachyarrhythmia",
			"description" = "A fast, disorganised rhythm that still perfuses the body. Cardiac drugs settle it; stimulants push it over into VF.",
			"symptom_pool" = list(
				/datum/affliction_symptom/rhythm_finding/tachy = 100,
				/datum/affliction_symptom/palpitations         = 80,
				/datum/affliction_symptom/dizziness            = 40,
				/datum/affliction_symptom/pallor               = 40,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 3,
			"consciousness_at_max" = 0,
			"factors" = alist(BF_HEART_RATE = 55, BF_BP_SYSTOLIC = -15, BF_PUMP = 0.85),
		),
		"VF" = list(
			"name" = "ventricular fibrillation",
			"description" = "The ventricles quiver without pumping. No pulse, no blood pressure. Shockable: defibrillate, and keep up CPR until the paddles are ready.",
			"symptom_pool" = list(
				/datum/affliction_symptom/rhythm_finding/vf = 100,
				/datum/affliction_symptom/absent_pulse      = 100,
				/datum/affliction_symptom/cyanosis          = 70,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 3,
			"consciousness_at_max" = 200,
			"factors" = alist(BF_PUMP = 0),
		),
		"Asystole" = list(
			"name" = "asystole",
			"description" = "A flatline. No electrical activity to shock. CPR and a vasopressor may coarsen it into VF, which can then be shocked.",
			"symptom_pool" = list(
				/datum/affliction_symptom/rhythm_finding/asystole = 100,
				/datum/affliction_symptom/absent_pulse            = 100,
				/datum/affliction_symptom/cyanosis                = 70,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 3,
			"consciousness_at_max" = 200,
			"factors" = alist(BF_PUMP = 0),
		),
	)
	return S

/datum/affliction/cardiac_arrhythmia/recompute_stage_from_severity()
	switch(rhythm)
		if(CARDIAC_RHYTHM_SINUS)
			_apply_stage("Sinus")
		if(CARDIAC_RHYTHM_TACHY)
			_apply_stage("Tachycardia")
		if(CARDIAC_RHYTHM_VF)
			_apply_stage("VF")
		else
			_apply_stage("Asystole")

/// Does this rhythm move blood?
/datum/affliction/cardiac_arrhythmia/proc/is_perfusing()
	return rhythm == CARDIAC_RHYTHM_SINUS || rhythm == CARDIAC_RHYTHM_TACHY

/// Can a defibrillator convert this rhythm?
/datum/affliction/cardiac_arrhythmia/proc/is_shockable()
	return rhythm == CARDIAC_RHYTHM_VF || rhythm == CARDIAC_RHYTHM_TACHY

/// Is someone doing chest compressions (a cardiac-output support)?
/datum/affliction/cardiac_arrhythmia/proc/is_receiving_compressions()
	return body?.is_supported(BF_PUMP)

/// Move to `new_rhythm`, resetting its severity and progression.
/datum/affliction/cardiac_arrhythmia/proc/set_rhythm(new_rhythm)
	rhythm = new_rhythm
	switch(rhythm)
		if(CARDIAC_RHYTHM_SINUS)
			progression_rate = -2
			set_severity(20)
		if(CARDIAC_RHYTHM_TACHY)
			progression_rate = 0.5
			set_severity(max(severity, 40))
		else
			progression_rate = 0
			set_severity(AFFLICTION_SEVERITY_TERMINAL)
	recompute_stage_from_severity()
	var/mob/living/carbon/human/H = owner
	if(istype(H) && !is_perfusing())
		H.pulse = PULSE_NONE
	if(body)
		body.invalidate(BODY_DIRTY_VITALS)

/// Electrical cardioversion. Returns TRUE if the rhythm converted.
/datum/affliction/cardiac_arrhythmia/proc/defibrillate()
	if(!is_shockable())
		return FALSE
	var/mob/living/carbon/human/H = owner
	var/obj/item/organ/internal/heart/heart = istype(H) ? H.internal_organs_by_name?[O_HEART] : null
	if(!heart || heart.is_broken())
		return FALSE
	set_rhythm(CARDIAC_RHYTHM_SINUS)
	return TRUE

/// Asystole + a vasopressor in the blood: chance the rhythm coarsens into VF.
/datum/affliction/cardiac_arrhythmia/proc/try_vasopressor_conversion()
	if(rhythm != CARDIAC_RHYTHM_ASYSTOLE || !body)
		return FALSE
	var/list/levels = body.treatment_levels()
	var/level = levels?[TREAT_VASOPRESSOR]
	if(!level || !prob(min(60, ARREST_VASOPRESSOR_CONVERSION * level)))
		return FALSE
	set_rhythm(CARDIAC_RHYTHM_VF)
	return TRUE

/// Instant mechanisms: shocks and compressions act on the rhythm, not severity.
/// Drugs (and everything else) can't settle a rhythm that isn't pumping them
/// anywhere.
/datum/affliction/cardiac_arrhythmia/receive_tagged_treatment(tag, amount, continuous = FALSE)
	switch(tag)
		if(TREAT_DEFIBRILLATION)
			return defibrillate() ? 1 : 0
		if(TREAT_CHEST_COMPRESSION)
			try_vasopressor_conversion()
			return 0
	if(!is_perfusing())
		return 0
	return ..()

/datum/affliction/cardiac_arrhythmia/tick()
	if(!is_perfusing())
		arrest_tick()
		if(QDELETED(src) || !body)
			return
	..()
	if(QDELETED(src) || !body)
		return
	if(rhythm == CARDIAC_RHYTHM_TACHY && severity >= AFFLICTION_SEVERITY_TERMINAL)
		set_rhythm(CARDIAC_RHYTHM_VF)

/// One tick without cardiac output: the rhythm drifts (VF fades to asystole,
/// slower under CPR; vasopressors coarsen asystole to VF). The lost output
/// itself is BF_PUMP 0, which the physiology turns into oxygen debt.
/datum/affliction/cardiac_arrhythmia/proc/arrest_tick()
	var/compressed = is_receiving_compressions()
	switch(rhythm)
		if(CARDIAC_RHYTHM_VF)
			if(prob(compressed ? ARREST_VF_DECAY_CHANCE / 2 : ARREST_VF_DECAY_CHANCE))
				set_rhythm(CARDIAC_RHYTHM_ASYSTOLE)
		if(CARDIAC_RHYTHM_ASYSTOLE)
			try_vasopressor_conversion()


// --- Human integration ----------------------------------------------------------------------

/// Is something stopping this mob taking a breath (closed airway, apnea)?
/mob/living/carbon/proc/breath_blocked()
	return FALSE

/// No air moves: the physiology's ventilation (drive, supports, mechanics and
/// airway together) is below the apnea threshold.
/mob/living/carbon/human/breath_blocked()
	var/ventilation = body?.ventilation()
	return !isnull(ventilation) && ventilation < PHYSIOLOGY_APNEA_VENTILATION

/// Is the upper airway closed? (Blocks rescue breaths and bag-valve masks too.)
/mob/living/carbon/human/proc/airway_obstructed()
	for(var/datum/affliction/airway/A in body?.afflictions)
		if(A.blocks_airway())
			return TRUE
	return FALSE

/mob/living/carbon/human/proc/cardiac_arrhythmia()
	RETURN_TYPE(/datum/affliction/cardiac_arrhythmia)
	return body?.find_affliction(/datum/affliction/cardiac_arrhythmia)

/// Is the heart moving blood? (No heart organ is handled by the pulse code.)
/mob/living/carbon/human/proc/has_cardiac_output()
	var/datum/affliction/cardiac_arrhythmia/A = cardiac_arrhythmia()
	return !A || A.is_perfusing()

/// Push the heart into `rhythm` (only ever toward a worse rhythm).
/mob/living/carbon/human/proc/induce_arrhythmia(rhythm = CARDIAC_RHYTHM_VF)
	if(!should_have_organ(O_HEART) || !internal_organs_by_name?[O_HEART])
		return null
	var/datum/affliction/cardiac_arrhythmia/A = cardiac_arrhythmia()
	if(A)
		if(rhythm > A.rhythm)
			A.set_rhythm(rhythm)
		return A
	A = body?.afflict(/datum/affliction/cardiac_arrhythmia)
	if(A && A.rhythm != rhythm)
		A.set_rhythm(rhythm)
	return A

/// Deliver a shock across the heart. TRUE if a shockable rhythm converted.
/mob/living/carbon/human/proc/defibrillate_heart()
	return mend(TREAT_DEFIBRILLATION, 1) > 0

/// What a cardiac monitor shows.
/mob/living/carbon/human/proc/cardiac_rhythm_reading()
	if(!should_have_organ(O_HEART) || !internal_organs_by_name?[O_HEART])
		return "no cardiac activity"
	var/datum/affliction/cardiac_arrhythmia/A = cardiac_arrhythmia()
	if(A)
		switch(A.rhythm)
			if(CARDIAC_RHYTHM_SINUS)
				return "sinus rhythm (recovering)"
			if(CARDIAC_RHYTHM_TACHY)
				return "irregular tachycardia"
			if(CARDIAC_RHYTHM_VF)
				return "ventricular fibrillation - SHOCKABLE"
		return "asystole - not shockable"
	if(stat == DEAD)
		return "no organised activity"
	return "normal sinus rhythm"


// --- Symptoms ----------------------------------------------------------------------------------

/datum/affliction_symptom/choking
	name = "choking"
	category = "Observable"
	subcategory = "Breathing"
	clinical_description = "Hands at the throat, unable to speak or breathe: a foreign body in the airway."
	examine_line = "They are clutching at their throat, unable to breathe."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 8
	scanner_phrase = "obstructed upper airway"

/datum/affliction_symptom/choking/get_patient_messages()
	var/static/list/L = list(
		"You can't breathe! Something is stuck in your throat!",
		"You try to cough, but nothing moves.",
	)
	return L

/datum/affliction_symptom/choking/get_public_emotes()
	var/static/list/L = list("clutches at their throat", "makes a strangled noise")
	return L

/datum/affliction_symptom/stridor
	name = "stridor"
	category = "Observable"
	subcategory = "Breathing"
	clinical_description = "A harsh, high-pitched noise on inspiration from a narrowed upper airway."
	examine_line = "Each breath comes with a harsh, high-pitched rasp."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 4
	scanner_phrase = "inspiratory stridor"

/datum/affliction_symptom/stridor/get_patient_messages()
	var/static/list/L = list("Your throat feels tight and narrow.", "Breathing in takes real effort.")
	return L

/datum/affliction_symptom/stridor/get_public_emotes()
	var/static/list/L = list("breathes with a harsh, whistling rasp")
	return L

/datum/affliction_symptom/facial_swelling
	name = "facial swelling"
	category = "Observable"
	subcategory = "Breathing"
	clinical_description = "Swollen lips, tongue and face — angioedema from an allergic reaction or burns."
	examine_line = "Their lips and face are puffy and swollen."
	audiences = SYMPTOM_AUDIENCE_PATIENT | SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 0
	scanner_phrase = "angioedema of the face and tongue"

/datum/affliction_symptom/facial_swelling/get_patient_messages()
	var/static/list/L = list("Your tongue feels too big for your mouth.", "Your lips are tingling and swollen.")
	return L

/datum/affliction_symptom/absent_breath_sounds
	name = "absent breath sounds"
	category = "Diagnosable"
	subcategory = "Breathing"
	clinical_description = "No chest rise and nothing heard over the lungs: the patient is not breathing."
	examine_line = "Their chest isn't moving."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 0
	scanner_phrase = "no spontaneous respiration"

/datum/affliction_symptom/agonal_gasping
	name = "agonal gasping"
	category = "Observable"
	subcategory = "Breathing"
	clinical_description = "Occasional reflexive gasps from a failing brainstem. Not real breathing."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 5
	scanner_phrase = "agonal respirations"

/datum/affliction_symptom/agonal_gasping/get_public_emotes()
	var/static/list/L = list("gasps once, then goes still")
	return L

/datum/affliction_symptom/diminished_breath_sounds
	name = "diminished breath sounds"
	category = "Diagnosable"
	subcategory = "Breathing"
	clinical_description = "Quiet or absent breath sounds over one side of the chest: a collapsed lung."
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "unilateral loss of breath sounds"

/datum/affliction_symptom/tracheal_deviation
	name = "tracheal deviation"
	category = "Observable"
	subcategory = "Breathing"
	clinical_description = "The windpipe shoved to one side by pressure in the chest: a tension pneumothorax."
	examine_line = "Their windpipe sits visibly off-centre and their neck veins bulge."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 0
	scanner_phrase = "tracheal deviation with distended neck veins"

/datum/affliction_symptom/absent_pulse
	name = "absent pulse"
	category = "Diagnosable"
	subcategory = "Circulation"
	clinical_description = "No palpable pulse and no measurable blood pressure: the heart is not pumping."
	examine_line = "They are deathly still and grey."
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	public_emote_chance = 0
	scanner_phrase = "no palpable pulse"

/datum/affliction_symptom/rhythm_finding
	name = "abnormal cardiac rhythm"
	category = "Diagnosable"
	subcategory = "Circulation"
	audiences = SYMPTOM_AUDIENCE_SCANNER

/datum/affliction_symptom/rhythm_finding/sinus
	name = "post-arrest sinus rhythm"
	clinical_description = "A restored, still-settling normal rhythm."
	scanner_phrase = "sinus rhythm with post-arrest ectopy"

/datum/affliction_symptom/rhythm_finding/tachy
	name = "tachyarrhythmia"
	clinical_description = "A fast, irregular rhythm that still perfuses."
	scanner_phrase = "irregular tachycardia"

/datum/affliction_symptom/rhythm_finding/vf
	name = "ventricular fibrillation"
	clinical_description = "Chaotic quivering with no output. Shockable."
	scanner_phrase = "ventricular fibrillation (shockable)"

/datum/affliction_symptom/rhythm_finding/asystole
	name = "asystole"
	clinical_description = "A flatline: no electrical activity. Not shockable."
	scanner_phrase = "asystole (not shockable)"

#undef ARREST_VF_DECAY_CHANCE
#undef ARREST_VASOPRESSOR_CONVERSION
#undef RESP_ARREST_APNEA_THRESHOLD
#undef PNEUMOTHORAX_TENSION_THRESHOLD
