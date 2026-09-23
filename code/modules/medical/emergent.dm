// Emergent afflictions: trigger dispatchers.
//
// Some afflictions are observations of catastrophic organ failure —
// respiratory_failure isn't a separate thing from "lungs at >70%
// damage"; cardiac_arrest isn't separate from "heart >70%". These
// afflictions auto-spawn when their target organ crosses an integrity
// threshold and auto-clear when it falls back below.
//
// The rule data lives entirely in /datum/affliction_trigger records
// (see code/modules/medical/causes/causes.dm). This file walks the
// organ_integrity / metric triggers and the chem-caused afflictions when
// their body invalidation domain (BODY_DIRTY_ORGANS / _METRICS / _CHEMS on
// body.dirty) is set: the base /mob/living on_reagent_change() and organ
// integrity changes mark them, Life() consumes them once per cycle. Everything
// lands in owner.body.

/mob/living/carbon/human
	var/dq_last_neural_load
	var/dq_last_radiation
	var/dq_last_bodytemperature

/// Scalar metrics include environmental values that can be authored outside a
/// setter. Comparing this small fixed signature is cheaper and safer than
/// walking every condition/cause when nothing changed.
/mob/living/carbon/human/proc/dq_refresh_metric_dirty_state()
	var/current_neural = injury_load(INJURY_CATEGORY_NEURAL)
	if(current_neural == dq_last_neural_load && radiation == dq_last_radiation && bodytemperature == dq_last_bodytemperature)
		return
	dq_last_neural_load = current_neural
	dq_last_radiation = radiation
	dq_last_bodytemperature = bodytemperature
	body?.invalidate(BODY_DIRTY_METRICS)

/// Run the trigger domains the body has invalidated since last time.
/mob/living/carbon/human/proc/dq_process_dirty_medical_conditions()
	if(!body)
		return
	dq_refresh_metric_dirty_state()
	var/dirty = body.dirty & BODY_DIRTY_CONDITIONS
	body.dirty &= ~BODY_DIRTY_CONDITIONS
	if(dirty & BODY_DIRTY_ORGANS)
		dq_check_emergent_conditions()
	if(dirty & BODY_DIRTY_METRICS)
		dq_check_metric_conditions()
	if(dirty & BODY_DIRTY_CHEMS)
		dq_check_chem_conditions()
		reconcile_medical_side_effects()

/mob/living/carbon/human/proc/dq_check_emergent_conditions()
	if(stat == DEAD)
		return
	for(var/datum/affliction_trigger/organ_integrity/c as anything in affliction_triggers_of_kind("/datum/affliction_trigger/organ_integrity"))
		var/obj/item/organ/O = _dq_resolve_organ_on(src, c.organ)
		if(!O || !O.max_damage)
			continue
		var/dmg_pct
		if(istype(O, /obj/item/organ/external))
			var/obj/item/organ/external/E = O
			dmg_pct = ((E.get_trauma() + E.get_burn()) / O.max_damage) * 100
		else
			dmg_pct = (O.damage / O.max_damage) * 100
		_dq_apply_outcomes(O, c.produces, dmg_pct, c.threshold_pct)


/// Apply a list of /datum/affliction_trigger_outcome to the host organ, given
/// the current metric value (`metric`) and an optional cause-level
/// default threshold (`default_threshold`). Outcomes can map either:
///
///   (a) one condition_type per outcome (legacy, used when each
///       outcome is its own distinct condition), or
///   (b) several outcomes sharing one condition_type, where each
///       outcome carries a `tier` field — in which case the condition
///       supports stages and we pick the highest tier whose threshold
///       is met, applying that as the stage.
///
/// Either way: spawn the condition when at least one outcome's
/// threshold is met, set its severity continuously based on how far
/// past the lowest-threshold outcome we are, and cure when no outcome
/// is met.
/mob/living/carbon/human/proc/_dq_apply_outcomes(obj/item/organ/host, list/produces, metric, default_threshold)
	if(!body)
		return
	// Bucket outcomes by condition_type so staged conditions can pick
	// the highest tier that fits.
	var/list/by_type = list()
	for(var/datum/affliction_trigger_outcome/o as anything in produces)
		LAZYINITLIST(by_type[o.condition_type])
		by_type[o.condition_type] += o

	for(var/condition_type in by_type)
		var/list/outs = by_type[condition_type]
		// Find the lowest threshold (for severity scaling) and the
		// highest-tier outcome currently met.
		var/min_thresh = 200
		var/datum/affliction_trigger_outcome/active_outcome
		var/highest_thresh = -1
		for(var/datum/affliction_trigger_outcome/o as anything in outs)
			var/thresh = !isnull(o.threshold) ? o.threshold : default_threshold
			if(isnull(thresh))
				thresh = 0
			if(thresh < min_thresh)
				min_thresh = thresh
			if(metric >= thresh && thresh > highest_thresh)
				highest_thresh = thresh
				active_outcome = o

		var/datum/affliction/existing = body.find_affliction(condition_type, host)

		if(active_outcome)
			// Severity scales from the lowest-met-threshold to 100, so
			// healing pulls severity down naturally even within a single
			// stage band. Min_thresh is the floor, not active_outcome's
			// threshold, so the curve doesn't lurch at stage boundaries.
			var/span = max(1, 100 - min_thresh)
			var/target_severity = clamp((metric - min_thresh) / span * 100, 0, 100)
			if(existing)
				existing.set_severity(target_severity)
				if(active_outcome.tier && active_outcome.tier != existing.stage)
					existing._apply_stage(active_outcome.tier)
			else
				var/datum/affliction/N = body.afflict(condition_type, host)
				if(N)
					N.set_severity(target_severity)
					if(active_outcome.tier)
						N._apply_stage(active_outcome.tier)
		else if(existing)
			existing.cure()


/// Metric-driven conditions: walk every /datum/affliction_trigger/metric,
/// read the mob's scalar value, spawn / cure / update severity on the
/// host organ. Same continuous-severity pattern as organ_damage causes:
/// at threshold severity is 0, at the cause's `metric_max` (or a
/// per-cause default) severity is 100.
/mob/living/carbon/human/proc/dq_check_metric_conditions()
	if(stat == DEAD)
		return
	for(var/datum/affliction_trigger/metric/c as anything in affliction_triggers_of_kind("/datum/affliction_trigger/metric"))
		var/value = dq_get_metric(c.metric)
		var/obj/item/organ/host = _dq_resolve_organ_on(src, c.host_organ)
		if(!host)
			continue
		// For `<=` causes (cold exposure) we flip the metric so the
		// shared apply_outcomes helper still uses "value >= threshold"
		// internally. The thresholds in the cause are authored in the
		// flipped frame already (e.g. temp_below threshold = 20K below
		// normal).
		_dq_apply_outcomes(host, c.produces, value, 0)


/// Chem-presence conditions: walk every condition subtype that
/// declares `caused_by_chems`. Two models are supported:
///
///   Binary (chem_scaling = FALSE, default):
///     While every named reagent is in the body at or above its
///     threshold, the condition exists at severity 50. The moment any
///     chem drops below threshold, the condition is cleared. Used for
///     side effects and interactions — they're presence-gated.
///
///   Scaling (chem_scaling = TRUE):
///     Severity climbs while the chem is over its threshold, with the
///     climb rate scaled by how-far-over. When volume drops back under,
///     severity decays at chem_decay_per_tick — the condition LINGERS
///     after the dose clears. Used for overdoses: small over-doses
///     accrue mildly, big over-doses spawn fast.
///
/// Lives on the condition itself rather than in a wrapping cause datum
/// — the encyclopedia links these conditions directly to their causing
/// reagents.
/mob/living/carbon/human/proc/dq_check_chem_conditions()
	if(stat == DEAD || !body)
		return
	var/static/list/chem_caused_types
	if(isnull(chem_caused_types))
		chem_caused_types = list()
		for(var/T in subtypesof(/datum/affliction))
			var/datum/affliction/proto = dq_proto(T)
			if(length(proto.caused_by_chems))
				chem_caused_types += T

	for(var/T as anything in chem_caused_types)
		var/datum/affliction/proto = dq_proto(T)
		var/list/chems = proto.caused_by_chems
		if(!length(chems))
			continue

		var/obj/item/organ/host = _dq_resolve_organ_on(src, proto.caused_by_chems_organ)
		if(!host)
			continue
		var/datum/affliction/existing = body.find_affliction(T, host)

		if(proto.chem_scaling)
			_dq_apply_scaling_chem_condition(host, existing, T, proto, chems)
		else
			_dq_apply_binary_chem_condition(host, existing, T, chems)

	// External-cure effects: OD conditions (typically) drain the
	// severity of OTHER conditions on the patient. Lives in this
	// dispatcher so the effect fires every Life tick reliably, not
	// dependent on the OD condition's host organ ticking. Scales by
	// the OD condition's own severity so mild ODs drain mildly.
	//
	// The body keeps a by-type index, so target lookup is O(1) per type.
	for(var/datum/affliction/C as anything in body.afflictions?.Copy())
		// Scaling conditions own a time-based severity ramp/decay. Keep only this
		// domain scheduled until the condition reaches a terminal state.
		if(C.chem_scaling && C.severity > 0)
			body.invalidate(BODY_DIRTY_CHEMS)
		if(!length(C.od_cures_externally))
			continue
		var/sev_scale = C.severity / 100
		if(sev_scale <= 0)
			continue
		for(var/target_type in C.od_cures_externally)
			var/drop_per_tick = C.od_cures_externally[target_type] * sev_scale
			if(drop_per_tick <= 0)
				continue
			var/list/targets = body.afflictions_by_type?[target_type]
			if(!targets)
				continue
			for(var/datum/affliction/target as anything in targets.Copy())
				target.adjust_severity(-drop_per_tick)


/// Binary (presence-gated) chem condition: spawn at severity 50 when
/// every named reagent is over its threshold, clear instantly when any
/// drops below.
/mob/living/carbon/human/proc/_dq_apply_binary_chem_condition(obj/item/organ/host, datum/affliction/existing, condition_type, list/chems)
	var/all_present = TRUE
	for(var/reagent_id in chems)
		var/vol = _dq_chem_volume(src, reagent_id)
		if(!vol || vol < chems[reagent_id])
			all_present = FALSE
			break
	if(all_present)
		if(!existing)
			body.afflict(condition_type, host, 50)
	else if(existing)
		existing.cure()


/// Scaling (overdose-style) chem condition: severity climbs while the
/// chem is over threshold, decays when it's not. Lingers after the
/// dose clears. Climb rate scales with how-far-over so a small dose
/// barely registers and a huge dose spirals fast.
///
/// Multi-chem scaling causes — rare, but the framework supports them —
/// drive climb from the SMALLEST over-amount across the gate (any chem
/// at or below threshold halts the climb), and decay from the same
/// gate failure. That matches the intuitive "interaction OD" pattern.
/mob/living/carbon/human/proc/_dq_apply_scaling_chem_condition(obj/item/organ/host, datum/affliction/existing, condition_type, datum/affliction/proto, list/chems)
	var/min_over_amount = INFINITY
	for(var/reagent_id in chems)
		var/vol = _dq_chem_volume(src, reagent_id)
		var/over = vol - chems[reagent_id]
		if(over < min_over_amount)
			min_over_amount = over

	if(min_over_amount > 0)
		// Over threshold: severity climbs.
		if(!existing)
			existing = body.afflict(condition_type, host)
			if(!existing)
				return
		existing.adjust_severity(proto.chem_climb_per_unit * min_over_amount)
		_dq_apply_od_stage(existing)
		return

	// Under (or exactly at) threshold: existing condition decays.
	// If it has nothing to decay, cure it; otherwise tick it down.
	if(!existing)
		return
	existing.adjust_severity(-proto.chem_decay_per_tick)
	if(existing.severity <= 0)
		existing.cure()
		return
	_dq_apply_od_stage(existing)


/// Pick the OD stage from severity and apply it via the condition's
/// `_apply_stage` so the per-stage symptom pool / mechanical / vital
/// tables swap in. Three tiers: Mild (25-60), Severe (60-90), Critical
/// (90+). Sub-clinical below 25 — accumulating but no overt effects yet
/// (symptoms cleared, stage reset to null).
///
/// Each OD condition declares its own `get_stages()` with stage-specific
/// effect data; the dispatcher only owns the severity→stage_id mapping.
/proc/_dq_apply_od_stage(datum/affliction/existing)
	var/new_stage
	if(existing.severity >= 90)
		new_stage = "Critical"
	else if(existing.severity >= 60)
		new_stage = "Severe"
	else if(existing.severity >= 25)
		new_stage = "Mild"
	else
		new_stage = null
	if(new_stage == existing.stage)
		return
	if(!new_stage)
		// Sub-clinical: clear the stage-applied state so the patient has
		// no overt symptoms while severity ticks under threshold.
		existing.stage = null
		existing.active_symptoms = null
		existing.symptom_pool = null
		existing.spontaneous_emotes = null
		existing.last_reroll_band = -1
		existing.body?.invalidate(BODY_DIRTY_FACTORS)
		return
	existing._apply_stage(new_stage)


/// The patient's normal core temperature (species), 37°C when unknown.
/mob/living/carbon/human/proc/dq_normal_body_temperature()
	return species?.body_temperature || T0C + 37

/mob/living/carbon/human/proc/dq_get_metric(metric_name)
	switch(metric_name)
		if("radiation")
			return radiation
		if("accumulated_rads")
			return accumulated_rads
		if("temp_above")
			// Kelvin above the species' normal body temperature.
			return max(0, bodytemperature - dq_normal_body_temperature())
		if("temp_below")
			// Kelvin below the species' normal body temperature.
			return max(0, dq_normal_body_temperature() - bodytemperature)
	return 0


/// Ischemic damage: a sustained oxygen debt damages organs beyond just
/// the brain. The physiology already kills the brain past
/// DQ_HYPOXIA_BRAIN_DAMAGE debt; we extend that to liver / kidneys /
/// heart so prolonged shock causes the secondary-failure modes real
/// medicine cares about (acute kidney injury, shock liver, cardiogenic
/// shock from poor coronary perfusion).
///
/// Threshold is hypoxia severity 30 (the old "oxyloss >= 30% of max health"
/// gate), full rate at 60. Rates are deliberately slow: organs accumulate
/// damage only over minutes of unresolved hypoxia, not seconds.
#define DQ_ISCHEMIA_HYPOXIA_THRESHOLD 30
/mob/living/carbon/human/proc/dq_check_ischemic_damage()
	if(stat == DEAD)
		return
	var/hypoxia = oxygen_debt()
	if(hypoxia < DQ_ISCHEMIA_HYPOXIA_THRESHOLD)
		return
	// Damage scales with how far past threshold we are: at threshold,
	// minimum rate; at 2× threshold, maximum rate.
	var/scale = clamp((hypoxia - DQ_ISCHEMIA_HYPOXIA_THRESHOLD) / DQ_ISCHEMIA_HYPOXIA_THRESHOLD, 0, 1)
	// Per-tick damage to non-brain organs from sustained hypoxia. The brain
	// still takes the heaviest hit (the physiology's debt consequences). These are lower. Rates reflect each organ's
	// real-medicine ischemic sensitivity:
	//   kidneys > liver > eyes > heart > lungs
	for(var/tag in list(O_LIVER, O_KIDNEYS, O_HEART, O_EYES, O_LUNGS))
		var/obj/item/organ/internal/O = internal_organs_by_name?[tag]
		if(!O)
			continue
		if(O.robotic >= ORGAN_ROBOT)
			continue
		var/per_tick
		switch(tag)
			if(O_KIDNEYS) per_tick = 0.4 + 0.6 * scale  // most ischemia-sensitive
			if(O_LIVER)   per_tick = 0.3 + 0.5 * scale
			if(O_EYES)    per_tick = 0.2 + 0.4 * scale  // retinal ischemia
			if(O_HEART)   per_tick = 0.2 + 0.4 * scale
			if(O_LUNGS)   per_tick = 0.1 + 0.2 * scale  // small to avoid runaway feedback
		if(prob(60))  // not every tick; smooths the curve
			injure(INJURY_BLUNT, per_tick, O, affliction = /datum/affliction/lesion/ischemic_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

	// Gut ischemia: damaged intestine risks bacterial translocation.
	// Rather than damage the intestine outward, we raise its germ_level
	// — which feeds the existing wound_infection bridge already in
	// /obj/item/organ/process() via dq_bridge_germ_to_condition(). This
	// is the path real medicine warns about: prolonged shock → gut
	// translocation → systemic infection.
	if(scale > 0)
		var/obj/item/organ/internal/intestine/gut = internal_organs_by_name?[O_INTESTINE]
		if(gut && gut.robotic < ORGAN_ROBOT)
			gut.adjust_germ_level(round(1 + 3 * scale))


/// Resolve an organ tag to the right organ on a human. Tries external
/// (BP_*) first, then internal (O_*).
/proc/_dq_resolve_organ_on(mob/living/carbon/human/H, tag)
	if(!H)
		return null
	var/obj/item/organ/O = H.get_organ(tag)
	if(O)
		return O
	if(H.internal_organs_by_name)
		return H.internal_organs_by_name[tag]
	return null

