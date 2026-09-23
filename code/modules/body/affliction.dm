// /datum/affliction — the root cause of every harm to a body.
//
// An affliction has a severity (0..100) — or, for load afflictions, a load in
// points — and may progress over time, spawn complications, present symptoms,
// be treated by mechanism (treatment tags) and contribute to the body's
// vitals (pain, consciousness). It lives in a /datum/body, optionally located
// on a part (an organ, a robot component). See doc/body_architecture.md.
//
// Lifecycle: always constructed as `new type(location)`; configure(location)
// is the virtual hook for location-dependent setup. Only
// /datum/body/add_affliction() and remove_affliction() attach and detach.
// cure() is the normal way out. Symptoms are stateless singletons;
// `active_symptoms` holds their typepaths.
//
// Tick pipeline (tick()), shared by every affliction:
//   apply_treatment(body.treatment_levels())  - treated_by / worsened_by_tags /
//                                               cured_by / worsened_by
//   progress()                                - drift / progression
//   update_symptoms()
//   fire_progression_triggers()
// Subtypes customise ONLY receive_tagged_treatment() and progress().
/datum/affliction
	var/name = "affliction"
	/// Owning body. Null while detached (organ in a tray) or unattached.
	var/datum/body/body
	/// Convenience: body.owner. Null when detached.
	var/mob/living/owner
	/// The part this affliction sits on: an organ for humanoids, a robot
	/// component for robots (typed as organ for field access), or null when
	/// systemic.
	var/obj/item/organ/location

	/// Biologies this affliction can exist on (BIOLOGY_*). A body refuses to
	/// grow an affliction on a part whose biology isn't listed.
	var/biology = BIOLOGY_ORGANIC
	/// Body plans this affliction can exist on (BODY_PLAN_*). Anything that
	/// needs anatomy (organs, limbs, blood, consciousness) stays humanoid-only.
	var/body_plans = BODY_PLAN_HUMANOID
	/// On simple/machine bodies (no anatomy, no diagnosis), load added per
	/// tick at severity 100 in `injury_category` — how the affliction actually
	/// harms a creature. 0 = no ongoing harm there (mechanical effects and
	/// symptoms still apply).
	var/simple_load_rate = 0
	/// INJURY_CATEGORY_* this affliction counts toward for load queries
	/// (vitality readouts, analysers, medbots). Null = not an injury
	/// (side effects, interactions, infections).
	var/injury_category

	/// 0..AFFLICTION_SEVERITY_TERMINAL. Players never see this number.
	var/severity = 0
	/// Severity growth per tick with no treatment, × AFFLICTION_BASE_PROGRESSION.
	/// Negative = self-resolving.
	var/progression_rate = 1
	/// Severity added per point of injury when an injury merges into this
	/// affliction.
	var/severity_per_injury = 1

	/// Pain contributed at severity 100 (scales linearly).
	var/pain_at_max = 0
	/// Consciousness removed at severity 100 (scales linearly). 200 means the
	/// patient passes out at severity 50.
	var/consciousness_at_max = 0

	// --- Treatment ---
	/// TREAT_* -> severity decrease per tick at full treatment level.
	var/list/treated_by
	/// TREAT_* -> severity increase per tick at full level.
	var/list/worsened_by_tags
	/// reagent ID -> severity decrease per tick (one-off pairings; stacks with tags).
	var/list/cured_by
	/// reagent ID -> severity increase per tick.
	var/list/worsened_by
	/// reagent ID -> multiplier applied to OTHER afflictions' treatment by
	/// that reagent while this one is active (drug interaction markers).
	var/list/interferes_with

	// --- Chemical causation (side effects, interactions, overdoses) ---
	/// reagent ID -> minimum volume. While every listed reagent is present at
	/// threshold, the chem dispatcher keeps this affliction alive.
	var/list/caused_by_chems
	/// Severity change accumulated by continuous treatment this tick, folded
	/// into progress() (negative = improving).
	var/tmp/pending_treatment = 0
	/// Rate at which TREAT_RESTORATION (admin / magic / species restoration)
	/// repairs this affliction. 0 = restoration doesn't touch it.
	var/restoration_rate = 0
	/// Instant mends of this affliction draw on a budget shared with the
	/// other budgeted afflictions the same mend reaches (limb wounds: a kit
	/// heals N points across the limb, not N per wound).
	var/shares_mend_budget = FALSE

	/// Organ tag chem-caused afflictions mount on.
	var/caused_by_chems_organ = O_LIVER
	/// Severity scales with how far over threshold (overdoses) instead of binary.
	var/chem_scaling = FALSE
	var/chem_climb_per_unit = 0.3
	var/chem_decay_per_tick = 3
	/// affliction type -> severity drop per tick at severity 100 (OD cures).
	var/list/od_cures_externally

	// --- Organ damage ---
	var/organ_damage_threshold = 0
	/// INJURY_* kind, or "internal" for organ integrity damage.
	var/organ_damage_type
	var/organ_damage_per_tick = 0
	var/list/organ_damage_targets
	/// Lesion kind (/datum/affliction/lesion typepath) inflicted by "internal"
	/// organ damage. Null = the organ's default (chem-caused -> toxic injury).
	var/organ_lesion_type

	// --- Presentation ---
	var/clinical_description
	var/category = "General"
	var/subcategory
	/// symptom typepath -> weight 0..100
	var/list/symptom_pool
	var/min_symptoms = 1
	var/max_symptoms = 3
	var/last_reroll_band = -1
	/// Typepaths of presenting symptoms (singletons; see affliction_symptom()).
	var/list/active_symptoms
	/// Emotes the patient may perform on their own while this is active.
	var/list/spontaneous_emotes
	/// Per-tick chance (%) of one of `spontaneous_emotes`.
	var/spontaneous_emote_prob = 2
	var/last_scanned_severity = null
	/// Active stage id (see get_stages()).
	var/stage

/datum/affliction/New(location)
	..()
	src.location = location
	configure(location)

/datum/affliction/Destroy()
	if(body)
		body.remove_affliction(src)
	active_symptoms = null
	location = null
	return ..()

/// Location-dependent setup, run once at construction (location may be null:
/// systemic afflictions, reference prototypes). Virtual.
/datum/affliction/proc/configure(location)
	return


// --- Lifecycle hooks -----------------------------------------------------------

/// Can this affliction exist at `location` on `target_body`?
/datum/affliction/proc/can_afflict(datum/body/target_body, location)
	return (target_body.plan_flag & body_plans) && (target_body.biology_of(location) & biology)

/datum/affliction/proc/on_added()
	return

/datum/affliction/proc/on_removed()
	for(var/symptom_type in active_symptoms)
		affliction_symptom(symptom_type).on_resolve(owner, src)
	active_symptoms = null

/// Resolve and remove. The normal way an affliction ends.
/datum/affliction/proc/cure()
	if(body)
		body.remove_affliction(src)
	qdel(src)


// --- Severity -------------------------------------------------------------------

/// The sole runtime boundary for severity changes. Listeners (contracts,
/// telemetry) hear COMSIG_AFFLICTION_SEVERITY_CHANGED on the owning mob.
/datum/affliction/proc/set_severity(new_severity)
	var/old_severity = severity
	severity = clamp(new_severity, 0, AFFLICTION_SEVERITY_TERMINAL)
	if(severity == old_severity)
		return FALSE
	if(body)
		var/dirty = BODY_DIRTY_VITALS
		if(factors && round(severity / BF_SEVERITY_BAND) != factor_band)
			dirty |= BODY_DIRTY_FACTORS
		body.invalidate(dirty)
	if(owner)
		SEND_SIGNAL(owner, COMSIG_AFFLICTION_SEVERITY_CHANGED, src, old_severity)
	return TRUE

/datum/affliction/proc/adjust_severity(delta)
	return set_severity(severity + delta)

/// An injury merged into this affliction. Returns the amount applied (in
/// injury points).
/datum/affliction/proc/receive_injury(amount, kind, atom/source)
	adjust_severity(amount * severity_per_injury)
	return amount

/// Instant severity treatment of `amount`. Returns how much was actually
/// treated. Cures at zero. (Helper for receive_tagged_treatment.)
/datum/affliction/proc/receive_treatment(amount)
	var/before = severity
	adjust_severity(-amount)
	if(severity <= 0)
		cure()
	return before - severity

/// THE treatment override point. `tag` is the TREAT_* mechanism (null for a
/// direct cured_by reagent pairing); `amount` is already scaled by the rate.
/// `continuous` = this tick's share of a continuous source (reagents,
/// regeneration) delivered by apply_treatment(); otherwise an instant mend()
/// from a tool, machine, procedure or power. Returns the amount treated.
/// Base: continuous treatment accrues into this tick's progress(); instant
/// treatment reduces severity now.
/datum/affliction/proc/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(continuous)
		pending_treatment -= amount
		return amount
	return receive_treatment(amount)

/// Continuous worsening (worsened_by_tags / worsened_by) accrues into this
/// tick's progress().
/datum/affliction/proc/receive_worsening(amount)
	pending_treatment += amount

/// How strongly `tag` treats this affliction (0 = not at all).
/datum/affliction/proc/treatment_rate(tag)
	if(tag == TREAT_RESTORATION)
		return restoration_rate
	return treated_by?[tag] || 0

/// Value this affliction contributes to injury_load() queries.
/datum/affliction/proc/load_value()
	return severity

/datum/affliction/proc/pain_contribution()
	return pain_at_max * severity / AFFLICTION_SEVERITY_TERMINAL

/datum/affliction/proc/consciousness_penalty()
	return consciousness_at_max * severity / AFFLICTION_SEVERITY_TERMINAL


// --- Tick -------------------------------------------------------------------------

/// One Life tick while attached to a body: the shared pipeline. Subtypes that
/// override tick() for extra per-tick behaviour must call ..().
/datum/affliction/proc/tick()
	// A resolved affliction is detached from its body; it no longer ticks.
	if(QDELETED(src) || !body)
		return
	recompute_stage_from_severity()
	apply_treatment(body.treatment_levels())
	if(QDELETED(src) || !body)
		return
	progress()
	if(QDELETED(src) || !body)
		return
	update_symptoms()
	tick_spontaneous_emotes()
	fire_progression_triggers()
	if(organ_damage_type && severity >= organ_damage_threshold)
		_apply_organ_damage()

/// Detached tick (organ out of a body): severity drifts, nothing else.
/datum/affliction/proc/tick_offline()
	if(progression_rate <= 0)
		return
	set_severity(severity + AFFLICTION_BASE_PROGRESSION * progression_rate)

/// The shared continuous-treatment loop: direct reagent pairings
/// (cured_by / worsened_by) and treatment tags (treated_by /
/// worsened_by_tags) from the body's per-tick snapshot, each delivered through
/// receive_tagged_treatment(tag, amount, continuous = TRUE).
/datum/affliction/proc/apply_treatment(list/levels)
	pending_treatment = 0
	if(!body)
		return
	for(var/id in cured_by)
		var/scale = dq_chem_dose_scale(body.reagent_volume(id))
		if(scale <= 0)
			continue
		receive_tagged_treatment(null, cured_by[id] * scale * body.reagent_cure_modifier(id), TRUE)
		if(QDELETED(src) || !body)
			return
	for(var/id in worsened_by)
		var/scale = dq_chem_dose_scale(body.reagent_volume(id))
		if(scale > 0)
			receive_worsening(worsened_by[id] * scale)
	if(!levels)
		return
	var/part_biology = body.biology_of(location)
	for(var/tag in treated_by)
		var/level = levels[tag]
		if(!level || !(treatment_tag_biology(tag) & part_biology))
			continue
		receive_tagged_treatment(tag, treated_by[tag] * level, TRUE)
		if(QDELETED(src) || !body)
			return
	for(var/tag in worsened_by_tags)
		var/level = levels[tag]
		if(level)
			receive_worsening(worsened_by_tags[tag] * level)

/// THE progression override point: how severity moves this tick. Base:
/// progression_rate plus this tick's continuous treatment, snowballing with
/// severity. Wounds and lesions override (damage is their state).
/datum/affliction/proc/progress()
	var/drift = AFFLICTION_BASE_PROGRESSION * progression_rate
	if(drift > 0)
		drift *= body.get_factor(BF_PROGRESSION)
	var/delta = drift + pending_treatment
	pending_treatment = 0
	// Conditions snowball: 1x at 0, 2x at 50, 3x at 100. Cures scale too, so
	// late-stage afflictions are harder (not impossible) to drag back.
	delta *= (1 + severity / 50)
	delta *= damage_scaling()
	set_severity(severity + delta)
	if(severity <= 0)
		cure()

/// Re-roll symptoms when severity crosses a band, then tick the presenting ones.
/datum/affliction/proc/update_symptoms()
	var/band = round(severity / AFFLICTION_SYMPTOM_BAND)
	if(band != last_reroll_band)
		var/previous_band = last_reroll_band
		last_reroll_band = band
		roll_symptoms(previous_band < 0 ? 1 : band - previous_band)
	for(var/symptom_type in active_symptoms)
		affliction_symptom(symptom_type).tick(owner, src)

/// Multiplier on the per-tick delta from how hurt the patient is right now.
/// Base 1.0; subtypes consult blood volume, limb wounds, etc.
/datum/affliction/proc/damage_scaling()
	return 1.0

/// Walk progression triggers sourced from this affliction's type.
/datum/affliction/proc/fire_progression_triggers()
	for(var/datum/affliction_trigger/progression/gate as anything in affliction_progression_gates_from(type))
		if(severity < gate.threshold)
			continue
		for(var/datum/affliction_trigger_outcome/o as anything in gate.produces)
			if(!o.preconditions_met(body, pick_spawn_target(o.condition_type)))
				continue
			if(body.find_affliction(o.condition_type, pick_spawn_target(o.condition_type)))
				continue
			if(!prob(o.chance))
				continue
			spawn_child_affliction(o.condition_type)


// --- Stages -------------------------------------------------------------------

/// Per-stage table: stage id -> list("name", "description", "symptom_pool",
/// "min_symptoms", "max_symptoms", "factors", "spontaneous_emotes",
/// "spontaneous_emote_prob", "organ_damage_*", "always_spawns"). Return a
/// static list. A stage's "factors" (alist) replaces `factors` and applies
/// at full value.
/datum/affliction/proc/get_stages()
	return null

/datum/affliction/proc/recompute_stage_from_severity()
	return

/datum/affliction/proc/_apply_stage(new_stage)
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
	spontaneous_emotes = entry["spontaneous_emotes"]
	if(!isnull(entry["spontaneous_emote_prob"]))
		spontaneous_emote_prob = entry["spontaneous_emote_prob"]
	if(!isnull(entry["organ_damage_per_tick"]))
		organ_damage_per_tick = entry["organ_damage_per_tick"]
	if(!isnull(entry["organ_damage_type"]))
		organ_damage_type = entry["organ_damage_type"]
	if(!isnull(entry["organ_damage_targets"]))
		organ_damage_targets = entry["organ_damage_targets"]
	if(!isnull(entry["pain_at_max"]))
		pain_at_max = entry["pain_at_max"]
	if(!isnull(entry["consciousness_at_max"]))
		consciousness_at_max = entry["consciousness_at_max"]
	last_reroll_band = -1
	if(body)
		body.invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_FACTORS)
	if(islist(entry["always_spawns"]))
		for(var/T in entry["always_spawns"])
			if(body?.find_affliction(T, pick_spawn_target(T)))
				continue
			spawn_child_affliction(T)


// --- Symptoms ---------------------------------------------------------------------

/// Evolve `active_symptoms` from `symptom_pool`. Symptoms ACCUMULATE:
///  - symptoms no longer in the pool (stage change) resolve;
///  - band_change > 0: every absent pool entry rolls to surface, topped up
///    to min_symptoms; only newly-surfaced ones are trimmed to max_symptoms;
///  - band_change < 0: one symptom fades per band dropped, never below min.
/datum/affliction/proc/roll_symptoms(band_change = 1)
	var/list/kept = list()
	for(var/symptom_type in active_symptoms)
		if(symptom_pool && symptom_pool[symptom_type])
			kept += symptom_type
		else
			affliction_symptom(symptom_type).on_resolve(owner, src)
	active_symptoms = length(kept) ? kept : null
	if(!symptom_pool)
		return

	if(band_change < 0)
		for(var/i in 1 to -band_change)
			if(LAZYLEN(active_symptoms) <= min_symptoms)
				break
			var/symptom_type = pick_n_take(active_symptoms)
			affliction_symptom(symptom_type).on_resolve(owner, src)
		if(!LAZYLEN(active_symptoms))
			active_symptoms = null
		return

	var/list/surfacing = list()
	for(var/symptom_type in symptom_pool)
		if(!(symptom_type in active_symptoms) && prob(symptom_pool[symptom_type]))
			surfacing += symptom_type
	while(LAZYLEN(active_symptoms) + length(surfacing) < min_symptoms)
		var/list/leftovers = list()
		for(var/symptom_type in symptom_pool)
			if(!(symptom_type in active_symptoms) && !(symptom_type in surfacing))
				leftovers[symptom_type] = symptom_pool[symptom_type]
		if(!length(leftovers))
			break
		surfacing += pickweight(leftovers)
	while(length(surfacing) && LAZYLEN(active_symptoms) + length(surfacing) > max_symptoms)
		pick_n_take(surfacing)
	for(var/symptom_type in surfacing)
		LAZYADD(active_symptoms, symptom_type)
		affliction_symptom(symptom_type).on_present(owner, src)


// --- Spontaneous emotes -----------------------------------------------------------------
// Mechanical effects (slowdown, accuracy, dropped items, blocked actions) are
// body factors: see `factors` and code/modules/body/factors.dm.

/datum/affliction/proc/tick_spontaneous_emotes()
	if(!owner || !length(spontaneous_emotes))
		return
	if(prob(spontaneous_emote_prob))
		owner.emote(pick(spontaneous_emotes))


// --- Complications & organ damage ---------------------------------------------------

/datum/affliction/proc/pick_spawn_target(child_typepath)
	return location

/datum/affliction/proc/spawn_child_affliction(typepath)
	if(!body || !ispath(typepath, /datum/affliction))
		return null
	return body.afflict(typepath, pick_spawn_target(typepath))

/// Damage organs proportional to how far past organ_damage_threshold severity
/// is: 0 at threshold, organ_damage_per_tick at 100.
/datum/affliction/proc/_apply_organ_damage()
	if(!owner || !organ_damage_type || !organ_damage_per_tick)
		return
	var/span = AFFLICTION_SEVERITY_TERMINAL - organ_damage_threshold
	if(span <= 0)
		return
	var/amount = organ_damage_per_tick * clamp((severity - organ_damage_threshold) / span, 0, 1)
	if(amount <= 0)
		return
	if(organ_damage_type != "internal")
		// Systemic or located injury through the normal pipeline.
		var/zone
		if(length(organ_damage_targets))
			zone = organ_damage_targets[1]
		else if(istype(location, /obj/item/organ/external))
			var/obj/item/organ/external/E = location
			zone = E.organ_tag
		owner.injure(organ_damage_type, amount, zone, src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		return
	// "internal": organ integrity damage through the injury pipeline, aimed
	// at the organ. The lesion kind rides as the affliction.
	var/lesion = organ_lesion_type
	if(!lesion && length(caused_by_chems))
		lesion = /datum/affliction/lesion/toxic_injury
	var/hit_any = FALSE
	for(var/tag in organ_damage_targets)
		var/obj/item/organ/O = _resolve_organ(tag)
		if(!O)
			continue
		hit_any = TRUE
		owner.injure(INJURY_BLUNT, amount, O, src, affliction = lesion, flags = INJURE_IGNORE_RESISTANCE)
	if(!hit_any && istype(location, /obj/item/organ))
		owner.injure(INJURY_BLUNT, amount, location, src, affliction = lesion, flags = INJURE_IGNORE_RESISTANCE)

/datum/affliction/proc/_resolve_organ(tag)
	var/mob/living/carbon/human/H = owner
	if(!istype(H))
		return null
	return _dq_resolve_organ_on(H, tag)


// --- Helpers ----------------------------------------------------------------------------

/// Map a body volume to a dose-scale multiplier: 0u -> 0, standard dose -> 1,
/// capped at DQ_CHEM_DOSE_CAP.
/proc/dq_chem_dose_scale(volume)
	if(volume <= 0)
		return 0
	return min(volume / DQ_CHEM_STANDARD_DOSE, DQ_CHEM_DOSE_CAP)

/// Linear map of `value` in [low_val, high_val] onto [low_mult, high_mult].
/proc/dq_damage_scale(value, low_val, high_val, low_mult, high_mult)
	if(high_val <= low_val)
		return low_mult
	var/t = clamp((value - low_val) / (high_val - low_val), 0, 1)
	return low_mult + (high_mult - low_mult) * t

/// Sum of a reagent's volume across a mob's holders (the body's reagent
/// snapshot, rebuilt when reagents change).
/proc/_dq_chem_volume(mob/living/M, reagent_id)
	return M?.body ? M.body.reagent_volume(reagent_id) : 0

/proc/dq_drop_random_held(mob/living/carbon/human/H)
	var/list/candidates = list()
	for(var/obj/item/I in list(H.get_equipped_item(SLOT_ID_HAND_L), H.get_equipped_item(SLOT_ID_HAND_R)))
		candidates += I
	if(!length(candidates))
		return
	var/obj/item/picked = pick(candidates)
	H.drop_from_inventory(picked)
	to_chat(H, span_warning("Your fingers slip — you drop \the [picked]."))
