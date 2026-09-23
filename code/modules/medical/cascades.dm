// Damage-event dispatcher.
//
// Called from /obj/item/organ/external/create_wound() — the lowest-level
// damage funnel, where every limb injury becomes a wound affliction. Every
// wound creation flows through here: melee / projectile hits (injure() ->
// receive_injury() -> take_damage()), surgery failures, scripted events. We classify
// the wound, then walk every /datum/affliction_trigger/injury whose rule
// matches and roll its outcomes.
//
// The rules table itself lives in code/modules/medical/causes/
// — this file is now just dispatch. Adding a new injury-driven
// condition does not require editing this file.

/obj/item/organ/external/proc/dq_check_damage_cascades(type, damage)
	if(!owner || !ishuman(owner) || damage <= 0)
		return
	// Synthetic parts fire synthetic triggers (coolant leaks, actuator
	// faults…) instead of organic ones; each trigger declares its biology.
	var/part_biology = owner.body.biology_of(src)

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
	// (burn_shock, compartment_syndrome): the limb's wound load before this
	// wound (get_burn() / get_trauma()) plus the event damage.
	var/cumulative
	if(wound_class == "burn")
		cumulative = get_burn() + damage
	else
		cumulative = get_trauma() + damage

	dq_dispatch_damage_event(wound_class, organ_tag, damage, cumulative, src, part_biology)

	// Broken-bone class is its own pseudo-wound that fires when the
	// organ flips to ORGAN_BROKEN. We dispatch it here for free since
	// create_wound() is the wound funnel; the bone-fracture cause picks
	// it up via wound_class = "broken_bone".
	if(status & ORGAN_BROKEN)
		dq_dispatch_damage_event("broken_bone", organ_tag, damage, cumulative, src, part_biology)


/datum/affliction_trigger/injury
	/// Biologies of the injured part this trigger fires for.
	var/biology = BIOLOGY_ORGANIC

/proc/dq_dispatch_damage_event(wound_class, organ_tag, single_damage, cumulative_damage, obj/item/organ/target, part_biology = BIOLOGY_ORGANIC)
	for(var/datum/affliction_trigger/injury/c as anything in affliction_triggers_of_kind("/datum/affliction_trigger/injury"))
		if(!(c.biology & part_biology))
			continue
		if(!c.matches(wound_class, organ_tag, single_damage, cumulative_damage))
			continue
		for(var/datum/affliction_trigger_outcome/o as anything in c.produces)
			if(!o.preconditions_met(target.owner?.body, target))
				continue
			// Per-outcome min_damage override (uses affliction_trigger_outcome.threshold
			// as the field — same slot used by organ_damage causes for
			// their damage % thresholds). Lets one cause carry several
			// outcomes that activate at different damage levels.
			if(!isnull(o.threshold) && single_damage < o.threshold)
				continue
			if(!prob(dq_scaled_cascade_chance(o, single_damage)))
				continue
			target.spawn_affliction(o.condition_type)


/// Scale a damage-event outcome's spawn probability by how much the hit
/// exceeds its threshold. A wound exactly at the threshold rolls at the
/// authored base chance; a 2× threshold hit guarantees the spawn (100%);
/// in between, the chance scales linearly and is capped at 95% so there's
/// still a small element of luck up to the deterministic ceiling. This
/// makes massive trauma reliably seed cascades while keeping borderline
/// hits stochastic. If no threshold is declared, fall back to the base
/// chance — there's nothing to scale against.
/proc/dq_scaled_cascade_chance(datum/affliction_trigger_outcome/o, single_damage)
	if(isnull(o.threshold) || o.threshold <= 0)
		return o.chance
	var/ratio = single_damage / o.threshold
	if(ratio >= 2)
		return 100
	return min(round(o.chance * ratio), 95)


/proc/_dq_is_limb_tag(organ_tag)
	return organ_tag in list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG, BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT)


/// Give this organ's body an affliction located here (or on `target`).
/// Idempotent per (type, location).
/obj/item/organ/proc/spawn_affliction(condition_type, obj/item/organ/target = src)
	return owner?.body?.afflict(condition_type, target || src)
