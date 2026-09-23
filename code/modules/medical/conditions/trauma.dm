// Trauma / burn / infection conditions — first batch.
//
// All conditions live in the body, located on the affected organ. Each
// condition declares its own progression rate, cure/worsen reagents,
// cascade target(s), symptom pool, and vital effects. The framework in
// _condition.dm handles severity ticking and presentation.

// --- Bruising / hemorrhage ---

/datum/affliction/deep_bruising
	factors = alist(BF_HEART_RATE = 8)
	name = "deep bruising"
	category = "Soft Tissue"
	clinical_description = "Bruised soft tissue from a heavy impact. Sore, but the body heals it on its own given time."
	progression_rate = 1.0
	treated_by = list(TREAT_TISSUE_REPAIR = 0.6)
	symptom_pool = list(
		/datum/affliction_symptom/throbbing_pain    = 60,
		/datum/affliction_symptom/pallor            = 40,
		/datum/affliction_symptom/internal_pressure = 30,
	)
	min_symptoms = 1
	max_symptoms = 2

/datum/affliction/deep_bruising/damage_scaling()
	. = 1.0
	if(location)
		var/obj/item/organ/external/E = location
		if(istype(E))
			. *= dq_damage_scale(E.get_trauma(), 5, 50, 0.5, 2.0)

/datum/affliction/internal_hemorrhage
	name = "internal hemorrhage"
	category = "Circulation"
	clinical_description = "Bleeding into the body cavity from torn vessels. Symptoms are often subtle until enough blood has been lost to start affecting circulation."
	progression_rate = 1.0
	treated_by = list(TREAT_HEMOSTATIC = 1.4, TREAT_VESSEL_REPAIR = 1)
	worsened_by_tags = list(TREAT_STIMULANT = 1.0)  // stimulant raises BP, worsens bleed
	// min_symptoms = 0: this can present invisibly at low severity.
	// Doctors who don't measure vitals won't see it until shock starts.
	symptom_pool = list(
		/datum/affliction_symptom/abdominal_tenderness = 35,
		/datum/affliction_symptom/pallor               = 30,
		/datum/affliction_symptom/dizziness            = 25,
		/datum/affliction_symptom/internal_pressure    = 25,
	)
	min_symptoms = 0
	max_symptoms = 2
	// No heart-rate or blood-pressure factors: pulse and BP are derived from actual blood
	// volume in vitals.dm. The bleed itself drains blood, and that
	// drain shows up directly in the instrument readings.

// Active hemorrhage actively drains blood. Internal — no visible
// splatter, just a silent reduction of vessel volume. The patient's
// pulse and BP readings update through vitals.dm reading vessel directly.
/datum/affliction/internal_hemorrhage/tick()
	. = ..()
	if(severity <= 0 || !owner || !istype(owner, /mob/living/carbon/human))
		return
	var/mob/living/carbon/human/H = owner
	if(!H.vessel)
		return
	// 0.1 units/tick at severity 25, scales up to ~0.6 at severity 100.
	// Tick is ~2s, so a stable bleed at severity 50 drains ~0.3*30=9
	// units/min — meaningful next to a 560-volume baseline but slow
	// enough that doctors have a real window.
	var/drain = (severity / 100) * 0.6
	if(drain > 0)
		H.remove_blood(drain)

// Scales with brute damage on the affected organ AND with blood loss.
// A bleeder with a 60-dam stab on a half-empty body runs much faster
// than a 10-dam scratch on a fully-topped-off body.
/datum/affliction/internal_hemorrhage/damage_scaling()
	. = 1.0
	if(location)
		var/obj/item/organ/external/E = location
		if(istype(E))
			. *= dq_damage_scale(E.get_trauma(), 5, 60, 0.6, 2.5)
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		if(H.vessel && H.species)
			var/blood_now = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
			var/blood_max = H.species.blood_volume
			if(blood_max > 0)
				var/lost_frac = clamp(1 - (blood_now / blood_max), 0, 1)
				. *= dq_damage_scale(lost_frac, 0, 0.4, 1.0, 2.0)

/datum/affliction/hypovolemic_shock
	factors = alist(BF_O2_SAT = -5)
	name = "hypovolemic shock"
	category = "Circulation"
	clinical_description = "Circulatory collapse from heavy blood loss. The body can no longer perfuse its tissues, and shock takes over."
	progression_rate = 2.0
	treated_by = list(TREAT_BLOOD_RESTORE = 0.8)
	symptom_pool = list(
		/datum/affliction_symptom/pallor      = 80,
		/datum/affliction_symptom/dizziness   = 70,
		/datum/affliction_symptom/chills      = 60,
		/datum/affliction_symptom/short_breath = 50,
		/datum/affliction_symptom/confusion   = 30,
	)
	min_symptoms = 1
	max_symptoms = 3
	// Damages the heart at high severity (poor coronary perfusion);
	// downstream cardiac damage spawns cardiac_arrest via the emergent
	// system. The collapse itself is BF_CIRCULATION in the band tables:
	// the physiology turns lost perfusion into oxygen debt.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 2
	organ_damage_targets = list(O_HEART)

// Severity-scaled mechanical effects: even at low severity (perfusion
// just starting to fail), the patient feels weak. At high severity
// they're collapsing. This keeps the condition palpable in the early
// stages rather than waiting for organ damage to start at sev 60.
//
// Effects only change when the severity BAND crosses (<30, 30-60, 60+),
// so cache the current band and reallocate the dict only on band
// transition — was allocating fresh on every Life tick.
/datum/affliction/hypovolemic_shock
	var/_last_effect_band = -1
	/// This band's factor table, applied at full value.
	var/alist/band_factors

/datum/affliction/hypovolemic_shock/accumulate_factors(list/acc)
	factor_band = round(severity / BF_SEVERITY_BAND)
	return body_factor_accumulate(acc, band_factors, 1)

/datum/affliction/hypovolemic_shock/tick()
	. = ..()
	if(severity <= 0)
		return
	var/band
	if(severity >= 60)
		band = 2
	else if(severity >= 30)
		band = 1
	else
		band = 0
	if(band == _last_effect_band)
		return
	_last_effect_band = band
	// Band tables are applied at full value: set them through the stage
	// path so the body treats them as the band's own table.
	var/static/list/bands = list(
		list("factors" = alist(BF_SLOWDOWN = 0.3), "spontaneous_emotes" = list("sigh"), "spontaneous_emote_prob" = 2),
		list("factors" = alist(BF_SLOWDOWN = 0.8, BF_ACCURACY = -12, BF_MOTOR_CONTROL = 0.99, BF_CIRCULATION = 0.85), "spontaneous_emotes" = list("wobble", "shake"), "spontaneous_emote_prob" = 3),
		list("factors" = alist(BF_SLOWDOWN = 1.5, BF_ACCURACY = -25, BF_MOTOR_CONTROL = 0.96, BF_CIRCULATION = 0.5), "spontaneous_emotes" = list("stagger", "collapse", "groan"), "spontaneous_emote_prob" = 6),
	)
	var/list/entry = bands[band + 1]
	band_factors = entry["factors"]
	spontaneous_emotes = entry["spontaneous_emotes"]
	spontaneous_emote_prob = entry["spontaneous_emote_prob"]
	body?.invalidate(BODY_DIRTY_FACTORS)

// Driven entirely by how much blood the patient has left. Topping the
// patient back up via saline / blood-pack stops the runaway.
/datum/affliction/hypovolemic_shock/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		if(H.vessel && H.species)
			var/blood_now = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
			var/blood_max = H.species.blood_volume
			if(blood_max > 0)
				var/lost_frac = clamp(1 - (blood_now / blood_max), 0, 1)
				// At 0% lost the patient isn't actually in shock — barely
				// progresses. At 50%+ lost it races. Strongest scaler we
				// have because shock IS the loss.
				. *= dq_damage_scale(lost_frac, 0, 0.5, 0.3, 3.0)

// --- Fracture / blunt ---

/datum/affliction/untreated_fracture
	name = "untreated fracture"
	category = "Bone"
	clinical_description = "A bone broken and left unset. The surrounding tissue grinds against the fragments with every movement."
	progression_rate = 0.5
	// Osteodaxon promotes bone healing; bicaridine handles the
	// surrounding soft-tissue damage.
	treated_by = list(TREAT_BONE_REPAIR = 1.2, TREAT_BONE_SETTING = 1)
	worsened_by_tags = list(TREAT_STIMULANT = 0.5)
	symptom_pool = list(
		/datum/affliction_symptom/sharp_pain    = 80,
		/datum/affliction_symptom/throbbing_pain = 60,
	)
	min_symptoms = 1
	max_symptoms = 2

/// Fracture pain and slowdown are body factors, by region and by whether a
/// splint holds the bone still. A splint doesn't knit the bone; it cuts the
/// grinding (pain) and the limp.
/datum/affliction/untreated_fracture/get_stages()
	var/static/list/S = list(
		"Unset leg" = list(
			"name" = "untreated fracture",
			"description" = "A broken leg bone, unset and unsupported. Every step grinds the fragments.",
			"symptom_pool" = list(/datum/affliction_symptom/sharp_pain = 80, /datum/affliction_symptom/throbbing_pain = 60),
			"factors" = alist(BF_SLOWDOWN = 1.5, BF_PAIN = 15),
		),
		"Splinted leg" = list(
			"name" = "splinted fracture",
			"description" = "A broken leg bone held still by a splint.",
			"symptom_pool" = list(/datum/affliction_symptom/throbbing_pain = 40, /datum/affliction_symptom/sharp_pain = 20),
			"factors" = alist(BF_SLOWDOWN = 0.5, BF_PAIN = 5),
		),
		"Unset arm" = list(
			"name" = "untreated fracture",
			"description" = "A broken arm bone, unset and unsupported.",
			"symptom_pool" = list(/datum/affliction_symptom/sharp_pain = 80, /datum/affliction_symptom/throbbing_pain = 60),
			"factors" = alist(BF_ACCURACY = -15, BF_PAIN = 15),
		),
		"Splinted arm" = list(
			"name" = "splinted fracture",
			"description" = "A broken arm bone held still by a splint.",
			"symptom_pool" = list(/datum/affliction_symptom/throbbing_pain = 40, /datum/affliction_symptom/sharp_pain = 20),
			"factors" = alist(BF_ACCURACY = -5, BF_PAIN = 5),
		),
		"Unset" = list(
			"name" = "untreated fracture",
			"description" = "A broken bone, unset and unsupported.",
			"symptom_pool" = list(/datum/affliction_symptom/sharp_pain = 80, /datum/affliction_symptom/throbbing_pain = 60),
			"factors" = alist(BF_SLOWDOWN = 0.5, BF_PAIN = 15),
		),
		"Splinted" = list(
			"name" = "splinted fracture",
			"description" = "A broken bone held still by a splint.",
			"symptom_pool" = list(/datum/affliction_symptom/throbbing_pain = 40, /datum/affliction_symptom/sharp_pain = 20),
			"factors" = alist(BF_PAIN = 5),
		),
	)
	return S

/datum/affliction/untreated_fracture/on_added()
	. = ..()
	recompute_stage_from_severity()

/datum/affliction/untreated_fracture/recompute_stage_from_severity()
	var/obj/item/organ/external/E = location
	var/region = ""
	if(istype(E))
		switch(E.organ_tag)
			if(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
				region = " leg"
			if(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND)
				region = " arm"
	_apply_stage("[(istype(E) && E.splinted) ? "Splinted" : "Unset"][region]")

/datum/affliction/untreated_fracture/damage_scaling()
	. = 1.0
	if(location)
		var/obj/item/organ/external/E = location
		if(istype(E))
			. *= dq_damage_scale(E.get_trauma(), 10, 60, 0.6, 1.8)

// Mild head trauma. A single concussion is mostly an inconvenience —
// dead-end cascade, self-heals over time, just symptoms + mild
// mechanical penalty while it runs its course. A SECOND head hit while
// the concussion is active spawns subdural_hematoma instead (handled
// in cascades.dm).
/datum/affliction/concussion
	name = "concussion"
	category = "Brain"
	clinical_description = "A brief disruption of brain function from a blow to the head. The first one usually resolves on its own; a second on top of it is far more serious."
	progression_rate = -0.5  // negative — concussions heal on their own (~20 min from 100)
	// Synaptizine is the targeted neuro-repair drug; alkysine helps mildly;
	// paracetamol manages the headache without accelerating recovery.
	treated_by = list(TREAT_NEURAL_REPAIR = 0.7, TREAT_ANALGESIC = 0.2)
	symptom_pool = list(
		/datum/affliction_symptom/headache         = 70,
		/datum/affliction_symptom/dizziness        = 60,
		/datum/affliction_symptom/nausea           = 50,
		/datum/affliction_symptom/blurred_vision   = 50,
		/datum/affliction_symptom/confusion        = 40,
		/datum/affliction_symptom/unsteady_gait    = 70,
	)
	min_symptoms = 2
	max_symptoms = 4
	factors = alist(BF_SLOWDOWN = 0.4, BF_ACCURACY = -15)
	spontaneous_emotes = list("stumble", "shake their head")
	spontaneous_emote_prob = 3

// Concussions normally heal. Spawn this with an initial severity high
// enough to actually present symptoms before the negative progression
// drags it back down.
/datum/affliction/concussion/New()
	..()
	severity = 100

// --- Burns ---

// Burn shock comes in three stages, driven by how much of the body has
// been burned. Stage is recomputed every tick from cumulative limb burn load;
// as the patient's burns worsen (or heal), the condition's symptoms and
// mechanical effects shift to match. This lets one datum cover the full
// "light singe → near-fatal" spectrum without a separate condition per
// severity tier.
//
// Stage 1 (≤60 total burn):   "light" — pallor, chills, mild discomfort
// Stage 2 (60–120 total burn): "moderate" — adds dyspnea, slowdown,
//                              hypotension, can cascade to wound_infection
// Stage 3 (>120 total burn):   "severe" — full shock presentation, fast
//                              progression, hypovolemic cascade enabled
/datum/affliction/burn_shock
	name = "burn shock"
	category = "Burns"
	clinical_description = "Systemic shock following extensive thermal injury. The more of the body's surface is burned, the harder it gets to stabilise."
	progression_rate = 2.0
	treated_by = list(TREAT_BURN_CARE = 1.2, TREAT_CIRCULATORY = 0.4)
	// symptom_pool / factors / spontaneous emotes come from
	// get_stages() — burn_shock has three stages driven by cumulative
	// limb burn load across all external organs, swapped in tick().
	min_symptoms = 1
	max_symptoms = 2
	// Severe stage-3 burns crash the body's ability to hold fluid
	// balance: stage 3 lowers BF_CIRCULATION.

/datum/affliction/burn_shock/New()
	..()
	// Default to Stage 1 so a freshly-spawned burn_shock has a symptom
	// pool before tick gets to recompute from limb burns.
	_apply_stage("Stage 1")

/datum/affliction/burn_shock/get_stages()
	var/static/list/S = list(
		"Stage 1" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/pallor = 70,
				/datum/affliction_symptom/chills = 50,
			),
			"min_symptoms" = 1,
			"max_symptoms" = 2,
			"factors" = alist(BF_HEART_RATE = 10, BF_BP_SYSTOLIC = -5),
		),
		"Stage 2" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/pallor       = 80,
				/datum/affliction_symptom/chills       = 60,
				/datum/affliction_symptom/short_breath = 50,
				/datum/affliction_symptom/dizziness    = 40,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 3,
			"factors" = alist(BF_SLOWDOWN = 0.6, BF_HEART_RATE = 25, BF_BP_SYSTOLIC = -20, BF_BP_DIASTOLIC = -10),
			"spontaneous_emotes" = list("wince", "groan"),
			"spontaneous_emote_prob" = 4,
		),
		"Stage 3" = list(
			"symptom_pool" = list(
				/datum/affliction_symptom/pallor       = 90,
				/datum/affliction_symptom/chills       = 80,
				/datum/affliction_symptom/short_breath = 70,
				/datum/affliction_symptom/dizziness    = 60,
				/datum/affliction_symptom/confusion    = 40,
				/datum/affliction_symptom/cyanosis     = 50,
			),
			"min_symptoms" = 3,
			"max_symptoms" = 4,
			"factors" = alist(BF_SLOWDOWN = 1.4, BF_ACCURACY = -20, BF_MOTOR_CONTROL = 0.97, BF_HEART_RATE = 40, BF_BP_SYSTOLIC = -35, BF_BP_DIASTOLIC = -20, BF_CIRCULATION = 0.5),
			"spontaneous_emotes" = list("groan in pain", "collapse", "shudder"),
			"spontaneous_emote_prob" = 7,
		),
	)
	return S

/datum/affliction/burn_shock/tick()
	// Burn_shock computes its stage from cumulative burn damage on the
	// owner each tick (the metric isn't a simple mob scalar; it walks
	// every external organ).
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/total_burn = 0
		if(H.organs)
			for(var/obj/item/organ/external/E in H.organs)
				total_burn += E.get_burn()
		var/new_stage
		if(total_burn >= 120)
			new_stage = "Stage 3"
		else if(total_burn >= 60)
			new_stage = "Stage 2"
		else
			new_stage = "Stage 1"
		if(new_stage != stage)
			_apply_stage(new_stage)
	. = ..()

// Sums limb burn load across all external organs — more of the body burned
// runs the shock harder. 30 total burn damage ≈ baseline, 150 = ×3.
/datum/affliction/burn_shock/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/total_burn = 0
		if(H.organs)
			for(var/obj/item/organ/external/E in H.organs)
				total_burn += E.get_burn()
		. *= dq_damage_scale(total_burn, 20, 150, 0.6, 3.0)

// --- Infection ---

/datum/affliction/wound_infection
	name = "wound infection"
	category = "Infection"
	clinical_description = "Bacterial colonisation of an open wound. The dirtier the wound was when it was inflicted, the faster the infection takes hold."
	progression_rate = 0.5
	// Debridement (resection) cuts the colonised tissue out.
	treated_by = list(TREAT_ANTIMICROBIAL = 1.0, TREAT_RESECTION = 1)
	symptom_pool = list(
		/datum/affliction_symptom/fever_sensation = 60,
		/datum/affliction_symptom/chills          = 40,
		/datum/affliction_symptom/throbbing_pain  = 50,
		/datum/affliction_symptom/fatigue         = 40,
	)
	min_symptoms = 1
	max_symptoms = 3

// wound_infection severity is driven by the organ's germ_level on top
// of its base progression. The dirtier the wound, the faster systemic
// infection sets in. Once germs are cleaned out (antibiotics +
// disinfectant) the condition decays on its own — although the doctor
// can also push spaceacillin directly to drop severity faster than the
// germ-physics alone. Also pushes real body temperature up so a fever
// shows on the thermometer, not just on the readout.
/datum/affliction/wound_infection/tick()
	. = ..()
	if(!location || !owner)
		return
	// Modest fever — local infection, not systemic yet.
	if(severity > 0 && istype(owner, /mob/living/carbon/human))
		var/target_offset_k = (severity / 100) * 1.2
		owner.bodytemperature = min(owner.bodytemperature + target_offset_k * 0.1, BODYTEMP_NORMAL + 1.5)
	var/germ_level = location.germ_level
	// Above INFECTION_LEVEL_ONE the wound is actively feeding the
	// condition. The extra delta scales with how far past threshold
	// we are: each 1000 germs over threshold = +1.0/tick (on top of
	// base progression).
	if(germ_level > INFECTION_LEVEL_ONE)
		severity = min(severity + ((germ_level - INFECTION_LEVEL_ONE) / 1000), AFFLICTION_SEVERITY_TERMINAL)
	// Hysteresis: germs well below threshold means the wound has been
	// cleaned. Condition severity drifts down on its own.
	else if(germ_level < (INFECTION_LEVEL_ONE - 100))
		severity = max(severity - 0.2, 0)
		if(severity <= 0)
			cure()

