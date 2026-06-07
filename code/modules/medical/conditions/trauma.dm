// Trauma / burn / infection conditions — first batch.
//
// All conditions live in the affected organ's medical_issues list. Each
// condition declares its own progression rate, cure/worsen reagents,
// cascade target(s), symptom pool, and vital effects. The framework in
// _condition.dm handles severity ticking and presentation.

// --- Bruising / hemorrhage ---

/datum/medical_issue/condition/deep_bruising
	name = "deep bruising"
	category = "Soft Tissue"
	clinical_description = "Bruised soft tissue from a heavy impact. Sore, but the body heals it on its own given time."
	progression_rate = 1.0
	cured_by = list(REAGENT_ID_BICARIDINE = 0.6, REAGENT_ID_TRICORDRAZINE = 0.3)
	symptom_pool = list(
		/datum/medical_symptom/throbbing_pain    = 60,
		/datum/medical_symptom/pallor            = 40,
		/datum/medical_symptom/internal_pressure = 30,
	)
	min_symptoms = 1
	max_symptoms = 2

/datum/medical_issue/condition/deep_bruising/get_vital_effects()
	var/static/list/L = list("pulse_mod" = 8)
	return L

/datum/medical_issue/condition/deep_bruising/damage_scaling()
	. = 1.0
	if(affectedorgan)
		var/obj/item/organ/external/E = affectedorgan
		if(istype(E))
			. *= dq_damage_scale(E.brute_dam, 5, 50, 0.5, 2.0)

/datum/medical_issue/condition/internal_hemorrhage
	name = "internal hemorrhage"
	category = "Circulation"
	clinical_description = "Bleeding into the body cavity from torn vessels. Symptoms are often subtle until enough blood has been lost to start affecting circulation."
	progression_rate = 1.0
	cured_by = list(REAGENT_ID_TRICORDRAZINE = 0.8, REAGENT_ID_BICARIDAZE = 1.4)
	worsened_by = list(REAGENT_ID_HYPERZINE = 1.0)  // stimulant raises BP, worsens bleed
	// min_symptoms = 0: this can present invisibly at low severity.
	// Doctors who don't measure vitals won't see it until shock starts.
	symptom_pool = list(
		/datum/medical_symptom/abdominal_tenderness = 35,
		/datum/medical_symptom/pallor               = 30,
		/datum/medical_symptom/dizziness            = 25,
		/datum/medical_symptom/internal_pressure    = 25,
	)
	min_symptoms = 0
	max_symptoms = 2
	// No vital_effects: pulse and BP are derived from actual blood
	// volume in vitals.dm. The bleed itself drains blood, and that
	// drain shows up directly in the instrument readings.

// Active hemorrhage actively drains blood. Internal — no visible
// splatter, just a silent reduction of vessel volume. The patient's
// pulse and BP readings update through vitals.dm reading vessel directly.
/datum/medical_issue/condition/internal_hemorrhage/tick_condition()
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
/datum/medical_issue/condition/internal_hemorrhage/damage_scaling()
	. = 1.0
	if(affectedorgan)
		var/obj/item/organ/external/E = affectedorgan
		if(istype(E))
			. *= dq_damage_scale(E.brute_dam, 5, 60, 0.6, 2.5)
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		if(H.vessel && H.species)
			var/blood_now = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
			var/blood_max = H.species.blood_volume
			if(blood_max > 0)
				var/lost_frac = clamp(1 - (blood_now / blood_max), 0, 1)
				. *= dq_damage_scale(lost_frac, 0, 0.4, 1.0, 2.0)

/datum/medical_issue/condition/hypovolemic_shock
	name = "hypovolemic shock"
	category = "Circulation"
	clinical_description = "Circulatory collapse from heavy blood loss. The body can no longer perfuse its tissues, and shock takes over."
	progression_rate = 2.0
	cured_by = list(REAGENT_ID_NUTRIMENT = 0.2, REAGENT_ID_IRON = 0.8)
	symptom_pool = list(
		/datum/medical_symptom/pallor      = 80,
		/datum/medical_symptom/dizziness   = 70,
		/datum/medical_symptom/chills      = 60,
		/datum/medical_symptom/short_breath = 50,
		/datum/medical_symptom/confusion   = 30,
	)
	min_symptoms = 1
	max_symptoms = 3
	// Pulse and BP both derive from actual blood volume already; only
	// the perfusion-related o2 sat needs an extra hit.
	// Damages the heart at high severity (poor coronary perfusion);
	// downstream cardiac damage spawns cardiac_arrest via the emergent
	// system. We also stack oxyloss directly — see the proc override
	// below.
	organ_damage_threshold = 60
	organ_damage_type = "internal"
	organ_damage_per_tick = 2
	organ_damage_targets = list(O_HEART)

/datum/medical_issue/condition/hypovolemic_shock/get_vital_effects()
	var/static/list/L = list("o2_sat_mod" = -5)
	return L

// Hypovolemic shock stacks oxyloss on top of the heart damage. Low
// blood means low perfusion means O2 transport collapses; upstream
// code converts that oxyloss into brain damage, which is what spawns
// anoxic_brain_injury via the emergent system. This is the natural
// path: bleed → shock → oxyloss → brain damage → ABI.
/datum/medical_issue/condition/hypovolemic_shock/_apply_organ_damage()
	..()
	if(!owner || severity < 60)
		return
	var/scale = clamp((severity - 60) / 40, 0, 1)
	owner.adjustOxyLoss(2.5 * scale)

// Severity-scaled mechanical effects: even at low severity (perfusion
// just starting to fail), the patient feels weak. At high severity
// they're collapsing. This keeps the condition palpable in the early
// stages rather than waiting for organ damage to start at sev 60.
//
// Effects only change when the severity BAND crosses (<30, 30-60, 60+),
// so cache the current band and reallocate the dict only on band
// transition — was allocating fresh on every Life tick.
/datum/medical_issue/condition/hypovolemic_shock
	var/_last_effect_band = -1

/datum/medical_issue/condition/hypovolemic_shock/tick_condition()
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
	switch(band)
		if(2)
			mechanical_effects = list(
				"slowdown" = 1.5,
				"accuracy_penalty" = 25,
				"drop_held_prob" = 4,
				"spontaneous_emotes" = list("stagger", "collapse", "groan"),
				"spontaneous_emote_prob" = 6,
			)
		if(1)
			mechanical_effects = list(
				"slowdown" = 0.8,
				"accuracy_penalty" = 12,
				"drop_held_prob" = 1,
				"spontaneous_emotes" = list("wobble", "shake"),
				"spontaneous_emote_prob" = 3,
			)
		else
			mechanical_effects = list(
				"slowdown" = 0.3,
				"spontaneous_emotes" = list("sigh"),
				"spontaneous_emote_prob" = 2,
			)

// Driven entirely by how much blood the patient has left. Topping the
// patient back up via saline / blood-pack stops the runaway.
/datum/medical_issue/condition/hypovolemic_shock/damage_scaling()
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

/datum/medical_issue/condition/untreated_fracture
	name = "untreated fracture"
	category = "Bone"
	clinical_description = "A bone broken and left unset. The surrounding tissue grinds against the fragments with every movement."
	progression_rate = 0.5
	// Osteodaxon promotes bone healing; bicaridine handles the
	// surrounding soft-tissue damage.
	cured_by = list(REAGENT_ID_OSTEODAXON = 1.0, REAGENT_ID_BICARIDINE = 0.3, REAGENT_ID_BICARIDAZE = 1.5)
	worsened_by = list(REAGENT_ID_HYPERZINE = 0.5)
	symptom_pool = list(
		/datum/medical_symptom/sharp_pain    = 80,
		/datum/medical_symptom/throbbing_pain = 60,
	)
	min_symptoms = 1
	max_symptoms = 2

/datum/medical_issue/condition/untreated_fracture/damage_scaling()
	. = 1.0
	if(affectedorgan)
		var/obj/item/organ/external/E = affectedorgan
		if(istype(E))
			. *= dq_damage_scale(E.brute_dam, 10, 60, 0.6, 1.8)

// Mild head trauma. A single concussion is mostly an inconvenience —
// dead-end cascade, self-heals over time, just symptoms + mild
// mechanical penalty while it runs its course. A SECOND head hit while
// the concussion is active spawns subdural_hematoma instead (handled
// in cascades.dm).
/datum/medical_issue/condition/concussion
	name = "concussion"
	category = "Brain"
	clinical_description = "A brief disruption of brain function from a blow to the head. The first one usually resolves on its own; a second on top of it is far more serious."
	progression_rate = -0.5  // negative — concussions heal on their own (~20 min from 100)
	// Synaptizine is the targeted neuro-repair drug; alkysine helps mildly;
	// paracetamol manages the headache without accelerating recovery.
	cured_by = list(REAGENT_ID_SYNAPTIZINE = 0.6, REAGENT_ID_ALKYSINE = 0.4, REAGENT_ID_PARACETAMOL = 0.2)
	symptom_pool = list(
		/datum/medical_symptom/headache         = 70,
		/datum/medical_symptom/dizziness        = 60,
		/datum/medical_symptom/nausea           = 50,
		/datum/medical_symptom/blurred_vision   = 50,
		/datum/medical_symptom/confusion        = 40,
		/datum/medical_symptom/unsteady_gait    = 70,
	)
	min_symptoms = 2
	max_symptoms = 4
	mechanical_effects = list(
		"slowdown" = 0.4,
		"accuracy_penalty" = 15,
		"spontaneous_emotes" = list("stumble", "shake their head"),
		"spontaneous_emote_prob" = 3,
	)

// Concussions normally heal. Spawn this with an initial severity high
// enough to actually present symptoms before the negative progression
// drags it back down.
/datum/medical_issue/condition/concussion/New()
	..()
	severity = 100

// --- Burns ---

// Burn shock comes in three stages, driven by how much of the body has
// been burned. Stage is recomputed every tick from cumulative burn_dam;
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
/datum/medical_issue/condition/burn_shock
	name = "burn shock"
	category = "Burns"
	clinical_description = "Systemic shock following extensive thermal injury. The more of the body's surface is burned, the harder it gets to stabilise."
	progression_rate = 2.0
	cured_by = list(REAGENT_ID_KELOTANE = 0.7, REAGENT_ID_DERMALINE = 1.2, REAGENT_ID_INAPROVALINE = 0.4)
	// symptom_pool / vital_effects / mechanical_effects come from
	// get_stages() — burn_shock has three stages driven by cumulative
	// burn_dam across all external organs, swapped in tick_condition().
	min_symptoms = 1
	max_symptoms = 2
	// Severe stage-3 burns crash the body's ability to hold fluid
	// balance; we model that as systemic oxyloss above stage 3.
	organ_damage_threshold = 70
	organ_damage_type = "oxy"
	organ_damage_per_tick = 3

/datum/medical_issue/condition/burn_shock/New()
	..()
	// Default to Stage 1 so a freshly-spawned burn_shock has a symptom
	// pool before tick_condition gets to recompute from burn_dam.
	_apply_stage("Stage 1")

/datum/medical_issue/condition/burn_shock/get_stages()
	var/static/list/S = list(
		"Stage 1" = list(
			"symptom_pool" = list(
				/datum/medical_symptom/pallor = 70,
				/datum/medical_symptom/chills = 50,
			),
			"min_symptoms" = 1,
			"max_symptoms" = 2,
			"vital_effects" = list("pulse_mod" = 10, "bp_sys_mod" = -5),
		),
		"Stage 2" = list(
			"symptom_pool" = list(
				/datum/medical_symptom/pallor       = 80,
				/datum/medical_symptom/chills       = 60,
				/datum/medical_symptom/short_breath = 50,
				/datum/medical_symptom/dizziness    = 40,
			),
			"min_symptoms" = 2,
			"max_symptoms" = 3,
			"vital_effects" = list("pulse_mod" = 25, "bp_sys_mod" = -20, "bp_dia_mod" = -10),
			"mechanical_effects" = list(
				"slowdown" = 0.6,
				"spontaneous_emotes" = list("wince", "groan"),
				"spontaneous_emote_prob" = 4,
			),
		),
		"Stage 3" = list(
			"symptom_pool" = list(
				/datum/medical_symptom/pallor       = 90,
				/datum/medical_symptom/chills       = 80,
				/datum/medical_symptom/short_breath = 70,
				/datum/medical_symptom/dizziness    = 60,
				/datum/medical_symptom/confusion    = 40,
				/datum/medical_symptom/cyanosis     = 50,
			),
			"min_symptoms" = 3,
			"max_symptoms" = 4,
			"vital_effects" = list("pulse_mod" = 40, "bp_sys_mod" = -35, "bp_dia_mod" = -20, "o2_sat_mod" = -8),
			"mechanical_effects" = list(
				"slowdown" = 1.4,
				"accuracy_penalty" = 20,
				"drop_held_prob" = 3,
				"spontaneous_emotes" = list("groan in pain", "collapse", "shudder"),
				"spontaneous_emote_prob" = 7,
			),
		),
	)
	return S

/datum/medical_issue/condition/burn_shock/tick_condition()
	// Burn_shock computes its stage from cumulative burn damage on the
	// owner each tick (the metric isn't a simple mob scalar; it walks
	// every external organ).
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/total_burn = 0
		if(H.organs)
			for(var/obj/item/organ/external/E in H.organs)
				total_burn += E.burn_dam
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

// Sums burn_dam across all external organs — more of the body burned
// runs the shock harder. 30 total burn damage ≈ baseline, 150 = ×3.
/datum/medical_issue/condition/burn_shock/damage_scaling()
	. = 1.0
	if(owner && istype(owner, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = owner
		var/total_burn = 0
		if(H.organs)
			for(var/obj/item/organ/external/E in H.organs)
				total_burn += E.burn_dam
		. *= dq_damage_scale(total_burn, 20, 150, 0.6, 3.0)

// --- Infection ---

/datum/medical_issue/condition/wound_infection
	name = "wound infection"
	category = "Infection"
	clinical_description = "Bacterial colonisation of an open wound. The dirtier the wound was when it was inflicted, the faster the infection takes hold."
	progression_rate = 0.5
	cured_by = list(REAGENT_ID_SPACEACILLIN = 1.0)
	symptom_pool = list(
		/datum/medical_symptom/fever_sensation = 60,
		/datum/medical_symptom/chills          = 40,
		/datum/medical_symptom/throbbing_pain  = 50,
		/datum/medical_symptom/fatigue         = 40,
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
/datum/medical_issue/condition/wound_infection/tick_condition()
	. = ..()
	if(!affectedorgan || !owner)
		return
	// Modest fever — local infection, not systemic yet.
	if(severity > 0 && istype(owner, /mob/living/carbon/human))
		var/target_offset_k = (severity / 100) * 1.2
		owner.bodytemperature = min(owner.bodytemperature + target_offset_k * 0.1, 310.15 + 1.5)
	var/germ_level = affectedorgan.germ_level
	// Above INFECTION_LEVEL_ONE the wound is actively feeding the
	// condition. The extra delta scales with how far past threshold
	// we are: each 1000 germs over threshold = +1.0/tick (on top of
	// base progression).
	if(germ_level > INFECTION_LEVEL_ONE)
		severity = min(severity + ((germ_level - INFECTION_LEVEL_ONE) / 1000), CONDITION_SEVERITY_TERMINAL)
	// Hysteresis: germs well below threshold means the wound has been
	// cleaned. Condition severity drifts down on its own.
	else if(germ_level < (INFECTION_LEVEL_ONE - 100))
		severity = max(severity - 0.2, 0)
		if(severity <= 0)
			cure_issue()

