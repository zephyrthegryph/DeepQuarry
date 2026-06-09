// Damage-event dispatcher.
//
// Called from /obj/item/organ/external/createwound() — the lowest-level
// damage funnel. Every wound creation flows through here: melee /
// projectile hits, surgery failures, scripted event damage. We classify
// the wound, then walk every /datum/dq_cause/damage_event whose rule
// matches and roll its outcomes.
//
// The rules table itself lives in code/modules/medical/causes/
// — this file is now just dispatch. Adding a new injury-driven
// condition does not require editing this file.

/obj/item/organ/external/proc/dq_check_damage_cascades(type, damage)
	if(!owner || !ishuman(owner) || damage <= 0)
		return
	if(robotic >= ORGAN_ROBOT)
		return

	var/wound_class
	if(type == CUT || type == PIERCE)
		wound_class = "sharp"
	else if(type == BRUISE)
		wound_class = "blunt"
	else if(type == BURN)
		wound_class = "burn"
	else
		return

	// Cumulative damage post-event for rules that gate on totals
	// (burn_shock, compartment_syndrome). For burn we use organ burn_dam
	// pre-update + the event damage; for sharp/blunt brute_dam + event.
	var/cumulative
	if(wound_class == "burn")
		cumulative = burn_dam + damage
	else
		cumulative = brute_dam + damage

	dq_dispatch_damage_event(wound_class, organ_tag, damage, cumulative, src)

	// Broken-bone class is its own pseudo-wound that fires when the
	// organ flips to ORGAN_BROKEN. We dispatch it here for free since
	// createwound() is the wound funnel; the bone-fracture cause picks
	// it up via wound_class = "broken_bone".
	if(status & ORGAN_BROKEN)
		dq_dispatch_damage_event("broken_bone", organ_tag, damage, cumulative, src)


/proc/dq_dispatch_damage_event(wound_class, organ_tag, single_damage, cumulative_damage, obj/item/organ/target)
	for(var/datum/dq_cause/damage_event/c as anything in dq_causes_of_kind("/datum/dq_cause/damage_event"))
		if(!c.matches(wound_class, organ_tag, single_damage, cumulative_damage))
			continue
		for(var/datum/dq_cause_outcome/o as anything in c.produces)
			if(!o.preconditions_met(target))
				continue
			// Per-outcome min_damage override (uses dq_cause_outcome.threshold
			// as the field — same slot used by organ_damage causes for
			// their damage % thresholds). Lets one cause carry several
			// outcomes that activate at different damage levels.
			if(!isnull(o.threshold) && single_damage < o.threshold)
				continue
			if(!prob(dq_scaled_cascade_chance(o, single_damage)))
				continue
			target.dq_spawn_condition(o.condition_type)


/// Scale a damage-event outcome's spawn probability by how much the hit
/// exceeds its threshold. A wound exactly at the threshold rolls at the
/// authored base chance; a 2× threshold hit guarantees the spawn (100%);
/// in between, the chance scales linearly and is capped at 95% so there's
/// still a small element of luck up to the deterministic ceiling. This
/// makes massive trauma reliably seed cascades while keeping borderline
/// hits stochastic. If no threshold is declared, fall back to the base
/// chance — there's nothing to scale against.
/proc/dq_scaled_cascade_chance(datum/dq_cause_outcome/o, single_damage)
	if(isnull(o.threshold) || o.threshold <= 0)
		return o.chance
	var/ratio = single_damage / o.threshold
	if(ratio >= 2)
		return 100
	return min(round(o.chance * ratio), 95)


/proc/_dq_is_limb_tag(organ_tag)
	return organ_tag in list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG, BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT)


/// Spawn a condition on this organ, idempotent — don't double-spawn the
/// same type. `target` defaults to `src` (use to spread to other organs).
/obj/item/organ/proc/dq_spawn_condition(condition_type, obj/item/organ/target = src)
	if(!ispath(condition_type, /datum/medical_issue/condition))
		return
	if(!target)
		target = src
	for(var/datum/medical_issue/condition/existing in target.medical_issues)
		if(existing.type == condition_type)
			return
	var/datum/medical_issue/condition/C = new condition_type()
	C.owner = owner
	C.affectedorgan = target
	LAZYADD(target.medical_issues, C)
