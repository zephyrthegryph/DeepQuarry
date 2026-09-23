// Vital systems — Airway, Breathing, Circulation — as afflictions.
//
// The ABCs of resuscitation, each a root-cause affliction with a mechanical
// consequence the body actually feels (no health pools):
//
//   Airway      airway_obstruction  choking / aspirated vomit / facial trauma
//               airway_edema        allergy / inhalation burns
//               A blocked airway means NO gas exchange: breathe() takes no
//               breath (/mob/living/carbon/proc/breath_blocked()).
//               Cure: TREAT_AIRWAY (Heimlich, airway kit), TREAT_VASOPRESSOR
//               (adrenaline / inaprovaline) for swelling.
//
//   Breathing   respiratory_arrest  opioid OD, brain herniation, deep hypoxia:
//                                   no spontaneous breathing while apneic.
//                                   TREAT_VENTILATION (bag-valve mask, CPR
//                                   rescue breaths) breathes FOR the patient.
//               pneumothorax        air trapped in the chest (chest pierce, a
//                                   perforated lung). Tension past severity 60.
//                                   TREAT_DECOMPRESSION (needle, chest tube)
//                                   vents it; a leaking lung perforation
//                                   re-fills it until surgery closes the hole.
//
//   Circulation cardiac_arrhythmia  rhythm state machine:
//                                   sinus (settling) / tachy (perfusing, unstable)
//                                   / VF (no output, shockable) / asystole
//                                   (no output, NOT shockable).
//               No output -> unconscious, tissue hypoxia and anoxic brain
//               lesions every tick. TREAT_CHEST_COMPRESSION (CPR) gives partial
//               perfusion. TREAT_DEFIBRILLATION converts VF / tachy only.
//               TREAT_VASOPRESSOR coaxes asystole back toward VF.
//
// Diagnosis is by symptom (singletons below, all SCANNER-visible) plus the
// rhythm readout on the health analyser and vitals monitor
// (cardiac_rhythm_reading()).

// --- Tuning ------------------------------------------------------------------------
/// Compressions count as ongoing for this long after the last cycle.
#define CPR_COMPRESSION_WINDOW (7 SECONDS)
/// Longest a single ventilation source can pre-load.
#define VENTILATION_MAX_WINDOW (30 SECONDS)
/// Fraction of arrest injury that still lands while CPR is ongoing.
#define ARREST_CPR_FACTOR 0.35
/// INJURY_ASPHYXIA per tick with no cardiac output.
#define ARREST_HYPOXIA_PER_TICK 2
/// Anoxic brain lesion damage per tick with no cardiac output.
#define ARREST_BRAIN_ISCHEMIA_PER_TICK 0.8
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
	factors = alist(BF_ACTION_BLOCKS = ACTION_BLOCK_SPEECH, BF_HEART_RATE = 15, BF_O2_SAT = -10)
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
	factors = alist(BF_HEART_RATE = 20, BF_BP_SYSTOLIC = -15, BF_O2_SAT = -8)
	spontaneous_emotes = list("cough", "gasp")
	spontaneous_emote_prob = 5

// --- Breathing ---------------------------------------------------------------------------

/// The patient has stopped breathing on their own.
/datum/affliction/respiratory_arrest
	factors = alist(BF_HEART_RATE = 10, BF_O2_SAT = -10)
	name = "respiratory arrest"
	category = "Respiratory"
	clinical_description = "The drive to breathe has failed — an opioid overdose, brain herniation or profound hypoxia. The heart may still beat, but no breaths are taken. Someone must breathe for the patient: a bag-valve mask, or rescue breaths during CPR. The drive returns once its cause is treated."
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	// The drive recovers on its own once nothing is suppressing it.
	progression_rate = -1
	// Ventilation doesn't cure: it breathes for the patient (see
	// receive_tagged_treatment). Respiratory stimulants hasten recovery.
	treated_by = list(TREAT_VENTILATION = 1.0, TREAT_STIMULANT = 0.4)
	symptom_pool = list(
		/datum/affliction_symptom/absent_breath_sounds = 100,
		/datum/affliction_symptom/cyanosis             = 70,
		/datum/affliction_symptom/agonal_gasping       = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	/// world.time until which someone is breathing for the patient.
	var/ventilated_until = 0

/datum/affliction/respiratory_arrest/on_added()
	. = ..()
	if(!severity)
		set_severity(AFFLICTION_SEVERITY_TERMINAL)

/// Not breathing on their own right now.
/datum/affliction/respiratory_arrest/proc/is_apneic()
	return severity >= RESP_ARREST_APNEA_THRESHOLD

/datum/affliction/respiratory_arrest/proc/is_ventilated()
	return world.time < ventilated_until

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

/// TREAT_VENTILATION: `amount` seconds of breaths delivered for the patient.
/datum/affliction/respiratory_arrest/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(tag == TREAT_VENTILATION)
		ventilated_until = min(max(ventilated_until, world.time) + amount * (1 SECONDS), world.time + VENTILATION_MAX_WINDOW)
		return 0
	return ..()


/// Air trapped in the pleural space, collapsing the lung.
/datum/affliction/pneumothorax
	name = "pneumothorax"
	category = "Chest"
	clinical_description = "Air has leaked into the chest cavity and is collapsing the lung. Left alone the pressure builds into a tension pneumothorax that crushes the heart's return and stops gas exchange. A decompression needle vents it in the field; a chest tube is definitive. If the lung itself is perforated, air keeps leaking back in until the hole is surgically repaired."
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	progression_rate = 1.0
	treated_by = list(TREAT_DECOMPRESSION = 1.0, TREAT_OXYGENATION = 0.3)
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
			"factors" = alist(BF_SLOWDOWN = 0.5, BF_O2_SAT = -6, BF_RESP_RATE = 6),
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
			"factors" = alist(BF_SLOWDOWN = 1.5, BF_ACCURACY = -20, BF_HEART_RATE = 25, BF_BP_SYSTOLIC = -25, BF_O2_SAT = -18, BF_RESP_RATE = 12),
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
	if(QDELETED(src) || !owner || severity < PNEUMOTHORAX_TENSION_THRESHOLD)
		return
	// Tension: gas exchange collapses on top of the lung damage.
	owner.injure(INJURY_ASPHYXIA, 1.5, source = src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

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
	/// world.time of the last CPR cycle.
	var/last_compression = 0

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
			"factors" = alist(BF_HEART_RATE = 55, BF_BP_SYSTOLIC = -15),
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

/datum/affliction/cardiac_arrhythmia/proc/is_receiving_compressions()
	return last_compression && world.time - last_compression <= CPR_COMPRESSION_WINDOW

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
			last_compression = world.time
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

/// One tick without cardiac output: oxygen debt, a dying brain, and the rhythm
/// drifting (VF fades to asystole; vasopressors coarsen asystole to VF).
/datum/affliction/cardiac_arrhythmia/proc/arrest_tick()
	var/mob/living/carbon/human/H = owner
	if(!istype(H))
		return
	var/compressed = is_receiving_compressions()
	var/factor = compressed ? ARREST_CPR_FACTOR : 1
	H.injure(INJURY_ASPHYXIA, ARREST_HYPOXIA_PER_TICK * factor, source = src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name?[O_BRAIN]
	if(istype(B) && B.robotic < ORGAN_ROBOT)
		H.injure(INJURY_BLUNT, ARREST_BRAIN_ISCHEMIA_PER_TICK * factor, B, src, affliction = /datum/affliction/lesion/ischemic_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	if(QDELETED(src) || !body)
		return
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

/mob/living/carbon/human/breath_blocked()
	if(airway_obstructed())
		return TRUE
	var/datum/affliction/respiratory_arrest/R = body?.find_affliction(/datum/affliction/respiratory_arrest)
	return R && R.is_apneic() && !R.is_ventilated()

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

#undef CPR_COMPRESSION_WINDOW
#undef VENTILATION_MAX_WINDOW
#undef ARREST_CPR_FACTOR
#undef ARREST_HYPOXIA_PER_TICK
#undef ARREST_BRAIN_ISCHEMIA_PER_TICK
#undef ARREST_VF_DECAY_CHANCE
#undef ARREST_VASOPRESSOR_CONVERSION
#undef RESP_ARREST_APNEA_THRESHOLD
#undef PNEUMOTHORAX_TENSION_THRESHOLD
