// Damage-emergent conditions.
//
// Some conditions are observations of catastrophic organ failure —
// respiratory_failure isn't a separate thing from "lungs at >70%
// damage"; cardiac_arrest isn't separate from "heart >70%". These
// conditions auto-spawn when their target organ crosses a damage
// threshold and auto-clear when it falls back below.
//
// The rule data lives entirely in /datum/dq_cause/organ_damage records
// (see code/modules/medical/causes/causes.dm). This file
// just walks those causes each Life tick.

/mob/living/carbon/human/proc/dq_check_emergent_conditions()
	if(stat == DEAD)
		return
	for(var/datum/dq_cause/organ_damage/c as anything in dq_causes_of_kind("/datum/dq_cause/organ_damage"))
		var/obj/item/organ/O = _dq_resolve_organ_on(src, c.organ)
		if(!O || !O.max_damage)
			continue
		var/dmg_pct
		if(istype(O, /obj/item/organ/external))
			var/obj/item/organ/external/E = O
			dmg_pct = ((E.brute_dam + E.burn_dam) / O.max_damage) * 100
		else
			dmg_pct = (O.damage / O.max_damage) * 100
		_dq_apply_outcomes(O, c.produces, dmg_pct, c.threshold_pct)


/// Apply a list of /datum/dq_cause_outcome to the host organ, given
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
	// Bucket outcomes by condition_type so staged conditions can pick
	// the highest tier that fits.
	var/list/by_type = list()
	for(var/datum/dq_cause_outcome/o as anything in produces)
		LAZYINITLIST(by_type[o.condition_type])
		by_type[o.condition_type] += o

	for(var/condition_type in by_type)
		var/list/outs = by_type[condition_type]
		// Find the lowest threshold (for severity scaling) and the
		// highest-tier outcome currently met.
		var/min_thresh = 200
		var/datum/dq_cause_outcome/active_outcome
		var/highest_thresh = -1
		for(var/datum/dq_cause_outcome/o as anything in outs)
			var/thresh = !isnull(o.threshold) ? o.threshold : default_threshold
			if(isnull(thresh))
				thresh = 0
			if(thresh < min_thresh)
				min_thresh = thresh
			if(metric >= thresh && thresh > highest_thresh)
				highest_thresh = thresh
				active_outcome = o

		// Find or remove an existing condition of this type.
		var/datum/medical_issue/condition/existing
		for(var/datum/medical_issue/condition/C in host.medical_issues)
			if(C.type == condition_type)
				existing = C
				break

		if(active_outcome)
			// Severity scales from the lowest-met-threshold to 100, so
			// healing pulls severity down naturally even within a single
			// stage band. Min_thresh is the floor, not active_outcome's
			// threshold, so the curve doesn't lurch at stage boundaries.
			var/span = max(1, 100 - min_thresh)
			var/target_severity = clamp((metric - min_thresh) / span * 100, 0, 100)
			if(existing)
				existing.severity = target_severity
				if(active_outcome.tier && active_outcome.tier != existing.stage)
					existing._apply_stage(active_outcome.tier)
			else
				var/datum/medical_issue/condition/N = new condition_type()
				N.owner = src
				N.affectedorgan = host
				N.severity = target_severity
				if(active_outcome.tier)
					N._apply_stage(active_outcome.tier)
				LAZYADD(host.medical_issues, N)
		else if(existing)
			existing.cure_issue()


/// Metric-driven conditions: walk every /datum/dq_cause/metric_threshold,
/// read the mob's scalar value, spawn / cure / update severity on the
/// host organ. Same continuous-severity pattern as organ_damage causes:
/// at threshold severity is 0, at the cause's `metric_max` (or a
/// per-cause default) severity is 100.
/mob/living/carbon/human/proc/dq_check_metric_conditions()
	if(stat == DEAD)
		return
	for(var/datum/dq_cause/metric_threshold/c as anything in dq_causes_of_kind("/datum/dq_cause/metric_threshold"))
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
	if(stat == DEAD)
		return
	var/static/list/chem_caused_types
	if(isnull(chem_caused_types))
		chem_caused_types = list()
		for(var/T in subtypesof(/datum/medical_issue/condition))
			var/datum/medical_issue/condition/proto = dq_proto(T)
			if(length(proto.caused_by_chems))
				chem_caused_types += T

	for(var/T as anything in chem_caused_types)
		var/datum/medical_issue/condition/proto = dq_proto(T)
		var/list/chems = proto.caused_by_chems
		if(!length(chems))
			continue

		var/obj/item/organ/host = _dq_resolve_organ_on(src, proto.caused_by_chems_organ)
		if(!host)
			continue
		var/datum/medical_issue/condition/existing
		for(var/datum/medical_issue/condition/C in host.medical_issues)
			if(C.type == T)
				existing = C
				break

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
	// Snapshot get_all_conditions() ONCE per tick and index by type —
	// the previous version was O(N²) (outer condition walk × inner
	// condition walk per target type). Polytrauma patients made this
	// hot.
	var/list/all_conditions = get_all_conditions()
	var/list/conditions_by_type = list()
	for(var/datum/medical_issue/condition/IC as anything in all_conditions)
		LAZYADDASSOCLIST(conditions_by_type, IC.type, IC)
	for(var/datum/medical_issue/condition/C as anything in all_conditions)
		if(!length(C.od_cures_externally))
			continue
		var/sev_scale = C.severity / 100
		if(sev_scale <= 0)
			continue
		for(var/target_type in C.od_cures_externally)
			var/drop_per_tick = C.od_cures_externally[target_type] * sev_scale
			if(drop_per_tick <= 0)
				continue
			var/list/targets = conditions_by_type[target_type]
			if(!targets)
				continue
			for(var/datum/medical_issue/condition/target as anything in targets)
				target.severity = max(0, target.severity - drop_per_tick)


/// Binary (presence-gated) chem condition: spawn at severity 50 when
/// every named reagent is over its threshold, clear instantly when any
/// drops below.
/mob/living/carbon/human/proc/_dq_apply_binary_chem_condition(obj/item/organ/host, datum/medical_issue/condition/existing, condition_type, list/chems)
	var/all_present = TRUE
	for(var/reagent_id in chems)
		var/vol = _dq_chem_volume(src, reagent_id)
		if(!vol || vol < chems[reagent_id])
			all_present = FALSE
			break
	if(all_present)
		if(!existing)
			var/datum/medical_issue/condition/N = new condition_type()
			N.owner = src
			N.affectedorgan = host
			N.severity = 50
			LAZYADD(host.medical_issues, N)
	else if(existing)
		existing.cure_issue()


/// Scaling (overdose-style) chem condition: severity climbs while the
/// chem is over threshold, decays when it's not. Lingers after the
/// dose clears. Climb rate scales with how-far-over so a small dose
/// barely registers and a huge dose spirals fast.
///
/// Multi-chem scaling causes — rare, but the framework supports them —
/// drive climb from the SMALLEST over-amount across the gate (any chem
/// at or below threshold halts the climb), and decay from the same
/// gate failure. That matches the intuitive "interaction OD" pattern.
/mob/living/carbon/human/proc/_dq_apply_scaling_chem_condition(obj/item/organ/host, datum/medical_issue/condition/existing, condition_type, datum/medical_issue/condition/proto, list/chems)
	var/min_over_amount = INFINITY
	for(var/reagent_id in chems)
		var/vol = _dq_chem_volume(src, reagent_id)
		var/over = vol - chems[reagent_id]
		if(over < min_over_amount)
			min_over_amount = over

	if(min_over_amount > 0)
		// Over threshold: severity climbs.
		if(!existing)
			var/datum/medical_issue/condition/N = new condition_type()
			N.owner = src
			N.affectedorgan = host
			N.severity = 0
			LAZYADD(host.medical_issues, N)
			existing = N
		existing.severity = min(100, existing.severity + proto.chem_climb_per_unit * min_over_amount)
		_dq_apply_od_stage(existing)
		return

	// Under (or exactly at) threshold: existing condition decays.
	// If it has nothing to decay, cure it; otherwise tick it down.
	if(!existing)
		return
	existing.severity -= proto.chem_decay_per_tick
	if(existing.severity <= 0)
		existing.cure_issue()
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
/proc/_dq_apply_od_stage(datum/medical_issue/condition/existing)
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
		existing.mechanical_effects = null
		existing.vital_effects = null
		existing.last_reroll_band = -1
		return
	existing._apply_stage(new_stage)


/// Sum of a reagent's volume across all body holders the cure-check
/// machinery considers. Mirrors dq_reagent_present's holder list so
/// presence and threshold agree on what counts.
/proc/_dq_chem_volume(mob/living/carbon/M, reagent_id)
	. = 0
	. += _dq_holder_reagent_volume(M.bloodstr, reagent_id)
	. += _dq_holder_reagent_volume(M.ingested, reagent_id)
	. += _dq_holder_reagent_volume(M.reagents, reagent_id)

/proc/_dq_holder_reagent_volume(datum/reagents/holder, reagent_id)
	if(!holder)
		return 0
	for(var/datum/reagent/R in holder.reagent_list)
		if(R.id == reagent_id)
			return R.volume
	return 0


/// Read a named scalar metric off the mob for metric_threshold causes.
/// Centralised so adding a new metric kind only requires one edit.
/mob/living/carbon/human/proc/dq_get_metric(metric_name)
	switch(metric_name)
		if("radiation")
			return radiation
		if("accumulated_rads")
			return accumulated_rads
		if("toxloss")
			return getToxLoss()
		if("oxyloss")
			return getOxyLoss()
		if("temp_above")
			// Kelvin above 310.15 (37°C).
			return max(0, bodytemperature - 310.15)
		if("temp_below")
			// Kelvin below 310.15 (37°C).
			return max(0, 310.15 - bodytemperature)
		if("cloneloss")
			return getCloneLoss()
	return 0


/// Ischemic damage: sustained oxyloss damages organs beyond just the
/// brain. Upstream already converts oxyloss to brain damage; we extend
/// that to liver / kidneys / heart so prolonged shock causes the
/// secondary-failure modes real medicine cares about (acute kidney
/// injury, shock liver, cardiogenic shock from poor coronary perfusion).
///
/// Threshold mirrors the upstream "oxyloss >= 30% of max health" gate
/// the brain damage path uses, so all three organ paths start together.
/// Rates are deliberately slow: organs accumulate damage only over
/// minutes of unresolved hypoxia, not seconds.
#define DQ_ISCHEMIA_OXY_THRESHOLD_PCT 0.30
/mob/living/carbon/human/proc/dq_check_ischemic_damage()
	if(stat == DEAD)
		return
	var/oxy = getOxyLoss()
	var/max_hp = getMaxHealth()
	if(max_hp <= 0)
		return
	if(oxy < (max_hp * DQ_ISCHEMIA_OXY_THRESHOLD_PCT))
		return
	// Damage scales with how far past threshold we are: at threshold,
	// minimum rate; at 2× threshold (60% of max_hp in oxyloss),
	// maximum rate.
	var/excess = (oxy - max_hp * DQ_ISCHEMIA_OXY_THRESHOLD_PCT) / (max_hp * DQ_ISCHEMIA_OXY_THRESHOLD_PCT)
	var/scale = clamp(excess, 0, 1)
	// Per-tick damage to non-brain organs from sustained hypoxia.
	// Brain still takes the heaviest hit (via upstream conversion at
	// 0.015 × oxyloss). These are lower. Rates reflect each organ's
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
			O.take_damage(per_tick, silent = TRUE)

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
