// /datum/medical_issue/condition — cascading medical condition.
//
// A condition is a /datum/medical_issue subtype that ticks severity up
// over time and can spawn child conditions (cascade) when it crosses a
// threshold. Treatments come from chems whose IDs are listed in
// `cured_by` and `worsened_by`. Player-observable presentation goes
// through `symptom_pool` — a weighted bag of /datum/medical_symptom subtypes
// from which a few are rolled active at any time.
//
// Conditions live in an organ's `medical_issues` list and tick from
// the organ's process() loop (every ~2s while in a mob).
//
// Resleeve clears all conditions. Death does not — bodies retain their
// conditions, which means recently-killed mobs that get revived inherit
// their pre-death medical state. That's intentional: revival isn't a
// reset, it's a window during which the doctor was able to stabilize
// before brain death. Resleeving a fresh body is the only true reset.
/datum/medical_issue/condition
	name = "condition"

	/// Internal severity counter, 0..CONDITION_SEVERITY_TERMINAL. Players
	/// never see this number; only the symptom presentation and band.
	var/severity = 0
	/// How fast severity grows per tick when not being cured. Multiplied
	/// by CONDITION_BASE_PROGRESSION.
	var/progression_rate = 1
	/// Severity gates that fire from this condition's progression are
	/// authored as /datum/dq_cause/severity_gate records in the causes
	/// module — see code/modules/medical/causes/causes.dm.
	/// tick_condition walks them via dq_severity_gates_from(type).

	/// reagent ID -> severity-decrease-per-tick. While any cured_by
	/// reagent is in the bloodstream, severity drops by that amount.
	var/list/cured_by
	/// reagent ID -> severity-increase-per-tick. Stacks with passive
	/// progression. Used for chems that are right for one condition
	/// but actively harmful for another.
	var/list/worsened_by
	/// reagent ID -> multiplier (0..N) applied to OTHER conditions'
	/// cure rate while THIS condition is active on the same patient.
	/// Used for drug-interaction markers — bicaridine + spaceacillin
	/// produces a "bicaridine_antibiotic_interference" condition whose
	/// `interferes_with = list(REAGENT_ID_SPACEACILLIN = 0.4)` makes
	/// spaceacillin only 40% as effective at curing whatever it would
	/// normally cure. Multipliers from multiple interference conditions
	/// compound — two interference conditions both listing the same
	/// reagent at 0.5 result in 0.25× total cure rate. > 1.0 is a
	/// boost; < 1.0 is interference; 0 is total block.
	var/list/interferes_with
	/// reagent ID -> minimum-volume threshold. While EVERY listed reagent
	/// is in the patient's body at or above its threshold, the dispatcher
	/// spawns this condition; when any drops below threshold, it clears.
	/// Used for drug side effects (single-reagent entry) and drug
	/// interactions (two-or-more-reagent entry) — replaces the older
	/// /datum/dq_cause/chem_presence indirection so the encyclopedia can
	/// link conditions directly to the reagents that cause them.
	/// Host organ for the spawned condition is `caused_by_chems_organ`.
	var/list/caused_by_chems
	/// Organ tag where chem-caused conditions mount. Read by the
	/// dispatcher; pick clinically relevant: brain for CNS effects,
	/// liver for metabolic side effects, heart for cardiac, etc.
	var/caused_by_chems_organ = O_LIVER
	/// If TRUE, severity scales with how-far-over the chem threshold
	/// rather than being binary. Used for overdoses: 1u over starts a
	/// slow climb; 20u over climbs fast. When volume drops back under
	/// threshold, severity decays gradually so the OD lingers after
	/// the dose clears. Side-effect / interaction conditions keep the
	/// binary spawn/clear model (TRUE here would be overkill).
	var/chem_scaling = FALSE
	/// Per-tick severity climb at exactly 1u over threshold. Higher =
	/// faster overdose. The dispatcher computes
	/// `delta = chem_climb_per_unit * over_amount`. Effective rate at
	/// 10u over = chem_climb_per_unit * 10.
	var/chem_climb_per_unit = 0.3
	/// Per-tick severity decay when the volume is back under threshold.
	/// Higher = OD clears faster. ~3 means a peak severity of 100 takes
	/// ~33 ticks (~66 seconds) to drift back to zero.
	var/chem_decay_per_tick = 3
	/// Conditions this one cures while it's active — keyed by
	/// /datum/medical_issue/condition typepath → severity drop per tick
	/// at severity 100. Scaled by THIS condition's severity (so a mild
	/// OD only mildly drains the target). Used for niche OD effects
	/// where overdosing one chem unlocks a path to clear an otherwise
	/// hard-to-reach condition (bicaridine OD → subdural hematoma, etc).
	/// The cured condition is found across all the patient's organs.
	var/list/od_cures_externally
	/// Positive effects contributed by this condition while active.
	/// Keyed by effect name → strength at severity 100. The aggregator
	/// (dq_od_boost_value) scales by severity automatically so mild ODs
	/// give a slice of the buff and severe ODs give it in full.
	///
	/// Effect keys:
	///   "speed"          — added to dq_condition_slowdown() (subtracted as boost)
	///   "accuracy"       — added to gunfire accuracy
	///   "pain_resist"    — proportion of pain ignored (1.0 = full immunity)
	///   "stun_resist"    — proportion of stun resisted
	///   "brute_heal"     — per-tick brute_dam removed
	///   "burn_heal"      — per-tick burn_dam removed
	///   "oxy_heal"       — per-tick oxyloss removed
	///   "tox_heal"       — per-tick toxloss removed
	///   "brain_repair"   — bonus brain organ repair per tick
	///   "heart_repair"   — bonus heart organ repair per tick
	///   "bleed_seal"     — per-tick bonus on internal_hemorrhage cure
	var/list/od_boost

	/// Severity threshold above which the condition starts damaging
	/// organs. Below this, the condition is symptomatic but not yet
	/// destroying tissue. 0 to disable organ damage entirely.
	var/organ_damage_threshold = 0
	/// Damage type to apply: BRUTE / BURN / "internal" (for internal
	/// organ.take_damage) / "oxy" / "tox". A null value disables organ
	/// damage.
	var/organ_damage_type
	/// Peak damage applied per tick when severity = 100. Scales
	/// linearly from threshold up to 100: at severity == threshold the
	/// rate is 0, at severity == 100 it's organ_damage_per_tick.
	var/organ_damage_per_tick = 0
	/// Organ tags the damage applies to. Empty list = damage applies
	/// to affectedorgan. Use this to make a condition that *lives* on
	/// the torso but damages the lungs (e.g. tension pneumothorax).
	var/list/organ_damage_targets

	/// Damage-emergent conditions are now declared via
	/// /datum/dq_cause/organ_damage records in the causes module. The
	/// emergent dispatcher in code/modules/medical/emergent.dm
	/// reads from there.

	/// One-sentence textbook overview for the reference book. Just
	/// "what is this thing."
	var/clinical_description

	/// Reference-book category. The book groups conditions by category
	/// in its index — body system or system class.
	/// Examples: "Brain", "Chest", "Limbs", "Circulation", "Eyes",
	/// "Infection", "Skin".
	var/category = "General"
	/// Optional finer-grained grouping rendered as a grey subheader
	/// inside a category. Use for clusters that share a sub-theme,
	/// like "Acute radiation" inside the "Radiation" category. Null
	/// means the condition sits directly under its category header
	/// with no subgroup.
	var/subcategory

	/// list of (typepath_of_/datum/medical_symptom = weight_0_100)
	var/list/symptom_pool
	/// Lower bound on active symptoms drawn from the pool. 0 means
	/// the condition can present invisibly.
	var/min_symptoms = 1
	/// Upper bound on active symptoms at once.
	var/max_symptoms = 3
	/// Last severity band we rolled at, so we know when to reroll.
	var/last_reroll_band = -1
	/// /datum/medical_symptom instances currently presenting.
	var/list/active_symptoms

	/// Effects this condition applies to vital readings. Two ways to
	/// populate:
	///  - Static per-subtype: override `get_vital_effects()` to return
	///    a `var/static/list/` local — shared across all instances of
	///    the subtype, no per-instance allocation.
	///  - Dynamic per-instance: assign `vital_effects = list(...)` at
	///    runtime (used by staged conditions like burn_shock that
	///    recompute on tick). The base `get_vital_effects()` returns
	///    this var when set, so a subtype can use either strategy.
	/// Keys: "pulse_mod" / "temp_mod_c" / "bp_sys_mod" / "bp_dia_mod"
	/// / "o2_sat_mod" / "resp_mod".
	var/list/vital_effects

	/// Severity at the last time a bodyscanner read this condition. Used
	/// to compute the trend arrow shown alongside scanner findings —
	/// medics see if their treatment is taking hold without needing the
	/// raw severity number. Null = not yet scanned (first scan emits
	/// "new" rather than a directional arrow).
	var/last_scanned_severity = null

	/// Active stage id, or null for non-staged conditions. Set by the
	/// emergent dispatcher (for organ-damage / metric conditions) or
	/// by the condition's own tick logic (burn_shock). When changed,
	/// `_apply_stage(new_id)` swaps the symptom_pool / mechanical /
	/// vital tables to the matching entry in `get_stages()`.
	var/stage

	// Suppress the upstream auto-process pathway. /datum/medical_issue's
	// handle_effects() does damage and reagent-cure work that doesn't
	// fit the condition model; we override and do our own.
	damagestrength = 0
	cure_reagent = null
	reagent_strength = 0
	symptom_text = null
	symptom_affect = null

/datum/medical_issue/condition/handle_effects()
	// Offline tick: organ has been removed from a body (severed limb on
	// the floor, organ in a tray). Conditions continue to progress —
	// necrosis worsens, infections fester — but they can't apply
	// body-level effects (no patient to slow down, no organ damage to
	// pile on). Severity-only path.
	if(!affectedorgan)
		return
	if(!owner)
		tick_offline()
		return
	if(!(affectedorgan in owner.organs) && !(affectedorgan in owner.internal_organs))
		return
	tick_condition()


/// Detached-organ tick. Severity drifts according to progression_rate
/// (no reagent metabolism, no damage scaling) so the condition keeps
/// developing on a severed limb. Skipped on negative-progression
/// conditions like concussion: a severed concussed head doesn't get
/// less concussed, but it doesn't make sense for it to keep healing
/// once detached either.
/datum/medical_issue/condition/proc/tick_offline()
	if(progression_rate <= 0)
		return
	var/delta = CONDITION_BASE_PROGRESSION * progression_rate
	severity = clamp(severity + delta, 0, CONDITION_SEVERITY_TERMINAL)

/// Returns the vital-effects table for this condition. Subtypes with
/// fixed effects should override to return a `var/static/list/` so the
/// list is shared across all instances. The base implementation falls
/// back to the per-instance `vital_effects` var, which only gets used
/// by stage-driven conditions (burn_shock) that mutate it on tick.
/datum/medical_issue/condition/proc/get_vital_effects()
	return vital_effects

/// Per-stage table for multi-stage conditions. Override on subtypes
/// that have stages; return a `var/static/list/` of stage-id -> entry,
/// where each entry is a list with keys:
///   "name"               — display name when this stage is active
///   "description"        — optional clinical-description override
///   "symptom_pool"       — symptom typepath -> weight
///   "min_symptoms"       — optional lower bound (defaults to instance value)
///   "max_symptoms"       — optional upper bound
///   "mechanical_effects" — slowdown / accuracy_penalty / etc
///   "vital_effects"      — pulse_mod / bp_sys_mod / etc
/// The book reads this map to render per-stage subsections. The
/// emergent dispatcher reads it to validate which stage_id values
/// the condition supports. Null = condition has no stages.
/datum/medical_issue/condition/proc/get_stages()
	return null

/// Recompute the active stage from the condition's own state. Default
/// implementation is no-op; subclasses with severity-driven stages
/// override this to call _apply_stage with the appropriate id. Called
/// from tick_condition every tick BEFORE the severity math runs, so a
/// surgery's severity drop (or a chem's gradual cure) can pull a
/// patient back to a milder stage. Dispatcher-driven conditions (heart_damage,
/// brain_damage) leave this alone — their stage is set by the emergent
/// dispatcher based on organ-damage %, not severity.
/datum/medical_issue/condition/proc/recompute_stage_from_severity()
	return

/// Swap the per-instance vars to the named stage's entry. Called when
/// the dispatcher or the condition's own tick decides the stage has
/// changed. Forces a symptom reroll on the next tick so the new pool
/// gets used.
/datum/medical_issue/condition/proc/_apply_stage(new_stage)
	if(new_stage == stage)
		return
	var/list/stages = get_stages()
	if(!stages || !stages[new_stage])
		return
	stage = new_stage
	var/list/entry = stages[new_stage]
	if(entry["name"])
		name = entry["name"]
	symptom_pool = entry["symptom_pool"]
	if(!isnull(entry["min_symptoms"]))
		min_symptoms = entry["min_symptoms"]
	if(!isnull(entry["max_symptoms"]))
		max_symptoms = entry["max_symptoms"]
	mechanical_effects = entry["mechanical_effects"]
	vital_effects = entry["vital_effects"]
	// OD-condition extensions: per-stage upside boosts and organ damage
	// rates can be authored alongside the symptom pool. Null entries
	// clear the previous stage's values so a milder stage doesn't carry
	// forward an aggressive stage's drain.
	od_boost = entry["od_boost"]
	if(!isnull(entry["organ_damage_per_tick"]))
		organ_damage_per_tick = entry["organ_damage_per_tick"]
	if(!isnull(entry["organ_damage_type"]))
		organ_damage_type = entry["organ_damage_type"]
	if(!isnull(entry["organ_damage_targets"]))
		organ_damage_targets = entry["organ_damage_targets"]
	last_reroll_band = -1  // force symptom reroll on next tick
	// always_spawns: list of /datum/medical_issue/condition typepaths
	// that this stage hardwires as complications. Each is spawned once
	// on entry to the stage (idempotent — already-present conditions
	// are skipped). Replaces the dq_cause/severity_gate cascade for
	// OD complications: the OD's own Critical stage is the cause, the
	// spawned condition is the effect, no separate cause datum needed.
	if(islist(entry["always_spawns"]))
		for(var/T in entry["always_spawns"])
			if(_dq_outcome_already_present(T))
				continue
			spawn_child_condition(T)

/datum/medical_issue/condition/proc/tick_condition()
	// Let staged conditions retreat to a lower stage if their severity has
	// dropped enough since last tick. Default no-op; severity-driven
	// staged subtypes override.
	recompute_stage_from_severity()

	// Reagent effects: cures lower, worsens raise. The authored rate is
	// the per-tick number at the standard dose (DQ_CHEM_STANDARD_DOSE
	// u in the patient's body). Sub-standard doses heal proportionally
	// slower; over-standard doses heal faster up to DQ_CHEM_DOSE_CAP×.
	// Stacks with per-reagent interaction modifiers
	// (dq_reagent_cure_modifier reads `interferes_with` markers on
	// other conditions on the same patient).
	//
	// Volume is summed across bloodstr and ingested — ingested chems
	// trickle into bloodstr and metabolize within the same Life tick,
	// so by the time conditions tick the bloodstr is briefly empty even
	// though the chem is actively medicating. Counting either holder
	// keeps swallowed pills working like injections.
	var/delta = CONDITION_BASE_PROGRESSION * progression_rate
	if(cured_by)
		for(var/id in cured_by)
			var/scale = dq_chem_dose_scale(dq_reagent_volume(id))
			if(scale <= 0)
				continue
			var/mod = owner?.dq_reagent_cure_modifier(id) || 1
			delta -= cured_by[id] * scale * mod
	if(worsened_by)
		for(var/id in worsened_by)
			// Worsen effects scale the same way — a massive overdose of
			// a contraindicated chem should hurt more than a trace.
			var/scale = dq_chem_dose_scale(dq_reagent_volume(id))
			if(scale <= 0)
				continue
			delta += worsened_by[id] * scale

	// Severity-driven acceleration: conditions snowball as they progress.
	// 1× at severity 0, 2× at 50, 3× at 100. Cures still scale too —
	// late-stage conditions are harder (not impossible) to drag back.
	delta *= (1 + severity / 50)
	// Damage-driven acceleration: a 60-damage stab should rack up
	// internal_hemorrhage faster than a 5-damage one. Each condition
	// declares what "damage" means for it (brute on this organ, burn
	// across all organs, blood volume below threshold, etc).
	delta *= damage_scaling()
	severity = clamp(severity + delta, 0, CONDITION_SEVERITY_TERMINAL)

	// Cure: dropped back to zero.
	if(severity <= 0)
		cure_issue()
		return

	// Roll/reroll symptoms when crossing a band boundary.
	var/band = round(severity / CONDITION_SYMPTOM_REROLL_STEP)
	if(band != last_reroll_band)
		last_reroll_band = band
		roll_symptoms()

	// Re-present active symptoms (drip messages / emote chances).
	for(var/datum/medical_symptom/S as anything in active_symptoms)
		S.tick(owner, src)

	// Apply stochastic mechanical effects (drop items, spontaneous
	// emotes). Continuous effects (slowdown, accuracy) are queried by
	// upstream code via dq_mechanical_value().
	tick_mechanical_effects()

	// Severity-gate causes: walk every /datum/dq_cause/severity_gate
	// whose source is this condition's type. Each gate rolls every
	// tick we're at or above its threshold until each outcome is
	// already present on the relevant organ (idempotent spawning
	// stops the re-roll naturally).
	for(var/datum/dq_cause/severity_gate/gate as anything in dq_severity_gates_from(type))
		if(severity < gate.threshold)
			continue
		for(var/datum/dq_cause_outcome/o as anything in gate.produces)
			if(!o.preconditions_met(affectedorgan))
				continue
			if(_dq_outcome_already_present(o.condition_type))
				continue
			if(!prob(o.chance))
				continue
			spawn_child_condition(o.condition_type)

	// Organ damage. Once severity climbs past the per-condition
	// threshold, the condition starts physically destroying the host
	// organ (or another organ; see organ_damage_targets). When that
	// damage drives a vital organ to its max, upstream `organ/die()`
	// triggers `owner.death()` — that's the actual cause of death in
	// the cascading-condition system. There's no separate "terminal
	// flag → die" path: death emerges from organ failure, the same as
	// it does for any other source of damage.
	if(organ_damage_type && severity >= organ_damage_threshold)
		_apply_organ_damage()


/// Is a reagent actively medicating the owner this tick? Returns TRUE
/// for any of: bloodstream, gut (still being absorbed), or the atom-level
/// holder (simple-mob carbons that lack the metabolism subsystem).
///
/// Why this exists: bloodstream-only checking misses pill / drink cures
/// because the metabolism subsystem moves chems from `ingested` to
/// `bloodstr` and then *consumes* them inside the same Life tick, so
/// the bloodstream is briefly empty by the time conditions tick. The
/// gut acts as a buffer that keeps the chem visible to the condition
/// check even when bloodstr has drained.
/datum/medical_issue/condition/proc/dq_reagent_present(id)
	if(!owner)
		return FALSE
	if(owner.bloodstr?.has_reagent(id))
		return TRUE
	if(owner.ingested?.has_reagent(id))
		return TRUE
	if(owner.reagents?.has_reagent(id))
		return TRUE
	return FALSE


/// Sum of a reagent's volume across the body's holders. Used by the
/// cure/worsen scaling logic — a chem's effect is proportional to how
/// much is in the body, capped at the dose-cap multiple. Returns 0 if
/// none is present.
/datum/medical_issue/condition/proc/dq_reagent_volume(id)
	. = 0
	if(!owner)
		return
	. += _dq_holder_reagent_volume(owner.bloodstr, id)
	. += _dq_holder_reagent_volume(owner.ingested, id)
	. += _dq_holder_reagent_volume(owner.reagents, id)


/// Map a body volume to a dose-scale multiplier. 0u = 0× (no effect),
/// standard dose = 1× (authored rate), dose cap = DQ_CHEM_DOSE_CAP×.
/// Linear ramp; above cap, no further bonus (and OD risk takes over).
/proc/dq_chem_dose_scale(volume)
	if(volume <= 0)
		return 0
	var/scale = volume / DQ_CHEM_STANDARD_DOSE
	if(scale > DQ_CHEM_DOSE_CAP)
		return DQ_CHEM_DOSE_CAP
	return scale


/// Picks a fresh `active_symptoms` set from `symptom_pool`. Each entry
/// is rolled against its weight; the count is clamped to [min,max].
/datum/medical_issue/condition/proc/roll_symptoms()
	var/list/old = active_symptoms?.Copy() || list()
	active_symptoms = list()
	if(!symptom_pool)
		return
	var/list/picked = list()
	for(var/type in symptom_pool)
		if(prob(symptom_pool[type]))
			picked += type
	while(length(picked) < min_symptoms && length(picked) < length(symptom_pool))
		// Force-include from leftovers, weighted.
		var/list/leftovers = list()
		for(var/type in symptom_pool)
			if(!(type in picked))
				leftovers[type] = symptom_pool[type]
		if(!length(leftovers))
			break
		picked += pickweight(leftovers)
	while(length(picked) > max_symptoms)
		picked.Cut(rand(1, length(picked)), rand(1, length(picked)) + 1)
	// Instantiate.
	for(var/type in picked)
		var/datum/medical_symptom/S = new type()
		S.source_condition = src
		active_symptoms += S
		S.on_present(owner, src)
	// Stop ones that left.
	for(var/datum/medical_symptom/old_s as anything in old)
		var/found = FALSE
		for(var/datum/medical_symptom/new_s as anything in active_symptoms)
			if(new_s.type == old_s.type)
				found = TRUE
				break
		if(!found)
			old_s.on_resolve(owner, src)

/// Is `typepath` already present on this condition's spawn target?
/datum/medical_issue/condition/proc/_dq_outcome_already_present(typepath)
	var/obj/item/organ/target = pick_spawn_target(typepath)
	if(!target)
		return FALSE
	for(var/datum/medical_issue/condition/existing in target.medical_issues)
		if(existing.type == typepath)
			return TRUE
	return FALSE

/// Spawn a child condition produced by a severity-gate cause. Targets
/// the same organ by default; subtypes can override pick_spawn_target.
/datum/medical_issue/condition/proc/spawn_child_condition(typepath)
	if(!ispath(typepath, /datum/medical_issue/condition))
		return
	var/obj/item/organ/target_organ = pick_spawn_target(typepath)
	if(!target_organ)
		return
	for(var/datum/medical_issue/condition/existing in target_organ.medical_issues)
		if(existing.type == typepath)
			return
	var/datum/medical_issue/condition/C = new typepath()
	C.owner = owner
	C.affectedorgan = target_organ
	LAZYADD(target_organ.medical_issues, C)

/datum/medical_issue/condition/proc/pick_spawn_target(child_typepath)
	return affectedorgan

/// Apply organ damage proportional to how far above
/// `organ_damage_threshold` the condition's severity is. Scales
/// linearly: 0 damage at threshold, `organ_damage_per_tick` at 100.
/// Damages every organ named in `organ_damage_targets`, or the
/// affectedorgan if that list is empty. The "type" string selects
/// which damage API to call.
/datum/medical_issue/condition/proc/_apply_organ_damage()
	if(!owner || !organ_damage_type || !organ_damage_per_tick)
		return
	var/span = CONDITION_SEVERITY_TERMINAL - organ_damage_threshold
	if(span <= 0)
		return
	var/scale = clamp((severity - organ_damage_threshold) / span, 0, 1)
	var/amount = organ_damage_per_tick * scale
	if(amount <= 0)
		return

	// Mob-wide damage types — apply directly to the owner.
	if(organ_damage_type == "oxy")
		owner.adjustOxyLoss(amount)
		return
	if(organ_damage_type == "tox")
		owner.adjustToxLoss(amount)
		return

	// Per-organ damage. Build the target list.
	var/list/targets = list()
	if(length(organ_damage_targets))
		for(var/tag in organ_damage_targets)
			var/obj/item/organ/O = _resolve_organ(tag)
			if(O)
				targets += O
	else if(affectedorgan)
		targets += affectedorgan

	for(var/obj/item/organ/O as anything in targets)
		if(istype(O, /obj/item/organ/external))
			var/obj/item/organ/external/E = O
			if(organ_damage_type == BURN)
				E.take_damage(0, amount, sharp = FALSE, edge = FALSE)
			else // BRUTE / default
				E.take_damage(amount, 0, sharp = FALSE, edge = FALSE)
		else
			O.take_damage(amount)

/// Resolve an organ tag to the correct organ on the owner. Tries
/// external first, then internal by name.
/datum/medical_issue/condition/proc/_resolve_organ(tag)
	if(!owner)
		return null
	var/mob/living/carbon/human/H = owner
	var/obj/item/organ/O = H.get_organ(tag)
	if(O)
		return O
	if(H.internal_organs_by_name)
		return H.internal_organs_by_name[tag]
	return null

/// Multiplier applied to per-tick severity delta based on how badly hurt
/// the patient is RIGHT NOW. Base returns 1.0 (no scaling). Override on
/// conditions that should accelerate with underlying damage:
///
///   - bleeders consult blood_volume (lower = faster shock)
///   - burns consult cumulative burn_dam (more burns = faster burn_shock)
///   - blunt/sharp conditions consult their organ's brute_dam
///
/// The convention is to return a multiplier in roughly [0.5, 3.0].
/// Returning <1 lets a treated/stable patient's condition slow naturally;
/// returning >1 makes a severely-injured patient's condition race.
/datum/medical_issue/condition/proc/damage_scaling()
	return 1.0

/// Helper: maps a `value` in range [low_val, high_val] to a multiplier
/// in [low_mult, high_mult] with clamping. Used by damage_scaling()
/// overrides to keep the math obvious.
/proc/dq_damage_scale(value, low_val, high_val, low_mult, high_mult)
	if(high_val <= low_val)
		return low_mult
	var/t = clamp((value - low_val) / (high_val - low_val), 0, 1)
	return low_mult + (high_mult - low_mult) * t

/datum/medical_issue/condition/cure_issue()
	for(var/datum/medical_symptom/S as anything in active_symptoms)
		S.on_resolve(owner, src)
	active_symptoms = null
	..()

// Lookup helper: walk all organs of a mob, gather conditions.
/mob/living/carbon/human/proc/get_all_conditions()
	. = list()
	if(organs)
		for(var/obj/item/organ/O as anything in organs)
			if(!O?.medical_issues)
				continue
			for(var/datum/medical_issue/condition/C in O.medical_issues)
				. += C
	if(internal_organs)
		for(var/obj/item/organ/O as anything in internal_organs)
			if(!O?.medical_issues)
				continue
			for(var/datum/medical_issue/condition/C in O.medical_issues)
				. += C


/// Product of every `interferes_with[reagent_id]` factor on every
/// active condition on this mob. Returns 1.0 if no condition interferes
/// — the no-op default. Used by tick_condition to scale a cure
/// reagent's contribution when an interaction is active (bicaridine
/// dampening spaceacillin, etc).
/mob/living/carbon/human/proc/dq_reagent_cure_modifier(reagent_id)
	. = 1.0
	for(var/datum/medical_issue/condition/C as anything in get_all_conditions())
		if(!C.interferes_with)
			continue
		var/factor = C.interferes_with[reagent_id]
		if(isnull(factor))
			continue
		. *= factor
