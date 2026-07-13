// Modern-AI port for /mob/living/simple_mob/metroid/juvenile — the wild,
// monkey-eating juvenile metroids.
//
// Legacy AI: /datum/ai_holder/simple_mob/juvenile_metroid
//   hostile = TRUE, cooperative = TRUE, firing_lanes = TRUE, mauling = TRUE,
//   conserve_ammo = TRUE, closest_desired_distance = 1.
//
//   on_engagement(): closed to melee range (1 tile) — it prefers to grab/shock
//     rather than plink.
//   pre_melee_attack(): intent machine —
//       DISARM (stun) a standing victim, with prob scaling on power_charge, or
//         always when always_stun is set;
//       GRAB (eat) a downed victim it can consume (juvenile + can_consume + lying);
//       else HURT.
//     The mob's apply_attack() reads a_intent to apply the matching effect, so
//     the behavior just sets a_intent then runs the normal attack.
//   closest_distance(): treated monkeys and downed/dying targets as melee range
//     so ranged metroids would walk up and eat instead of shooting.
//   can_attack(): monkeys (incl. alien monkeys) are always valid food.
//   handle_special_tactic() -> evolve_and_reproduce(): once nutrition hits the
//     evolution point, evolve to the next form.
//
// can_consume(), evolve(), the is_juvenile/power_charge/nutrition/evo_point
// vars, and apply_attack()'s intent dispatch all still live on the metroid mob.

/mob/living/simple_mob/metroid/juvenile
	use_modern_ai = TRUE
	/// When TRUE the metroid always opens with a stun (I_DISARM) attempt rather
	/// than rolling on power_charge. Lived on the legacy AI holder; kept here so
	/// admins / events can still force "always permastun" metroids.
	var/always_stun = FALSE

/mob/living/simple_mob/metroid/juvenile/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/metroid_evolve,
		/datum/ai_behavior/metroid_smart_attack,
		/datum/ai_behavior/ranged_attack,
		/datum/ai_behavior/approach_threat,
		// NOTE: no generic maul_unconscious — metroid_smart_attack's GRAB branch
		// already eats downed prey with the correct (consume) intent. The generic
		// maul would attack with the wrong a_intent and skip consumption.
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/follow_leader,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/metroid/juvenile/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/metroid_prefer_monkey,
		/datum/target_selector/closest,
	)
	return L

// ---------------------------------------------------------------------------
// Monkey-preferring target selector. Monkeys (incl. alien monkeys via istype)
// are the metroid's favourite food, so prefer them; otherwise nearest. Mirrors
// legacy can_attack()'s "monkeys are always food" plus the desire to eat them.
// ---------------------------------------------------------------------------

/datum/target_selector/metroid_prefer_monkey

/datum/target_selector/metroid_prefer_monkey/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	for(var/mob/living/M as anything in candidates)
		if(!ishuman(M))
			continue
		var/mob/living/carbon/human/H = M
		if(istype(H.species, /datum/species/monkey))
			return H
	var/datum/target_selector/closest_selector = dq_get_selector(/datum/target_selector/closest)
	return closest_selector.select(brain, candidates)

// ---------------------------------------------------------------------------
// Smart attack — intent machine. Prefers to close to melee (so it can shock /
// eat) rather than shoot; this behavior wins over ranged_attack whenever the
// target is adjacent, and approach_threat closes the gap otherwise.
// ---------------------------------------------------------------------------

/datum/ai_behavior/metroid_smart_attack
	name = "metroid maul"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1

/datum/ai_behavior/metroid_smart_attack/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/metroid/juvenile)

/datum/ai_behavior/metroid_smart_attack/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/metroid/juvenile/MJ = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(MJ) || !threat || !MJ.Adjacent(threat))
		return null
	if(!MJ.checkClickCooldown())
		return null
	// Score above ranged_attack so the metroid always prefers to grab/shock in
	// melee, matching the legacy closest_desired_distance = 1 behavior.
	return DQAI_RESULT(50, threat)

/datum/ai_behavior/metroid_smart_attack/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/metroid/juvenile/MJ = brain.holder
	if(!istype(MJ) || !isliving(target))
		return DQ_BEHAVIOR_FAILED
	var/mob/living/L = target
	// Intent selection, faithful to legacy pre_melee_attack():
	if((!L.lying && prob(30 + (MJ.power_charge * 7))) || (!L.lying && MJ.always_stun))
		MJ.a_intent = I_DISARM           // Stun the standing target first.
	else if(MJ.is_juvenile && MJ.can_consume(L) && L.lying)
		MJ.a_intent = I_GRAB             // Then eat the downed target.
	else
		MJ.a_intent = I_HURT             // Otherwise just hurt it.
	MJ.attack_target(L)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Evolve — once fed enough, advance to the next metroid form. Mirrors legacy
// handle_special_tactic() -> evolve_and_reproduce(). Background priority so it
// only fires when the metroid isn't busy fighting.
// ---------------------------------------------------------------------------

/datum/ai_behavior/metroid_evolve
	name = "metroid evolve"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE
	cooldown = 5 SECONDS

/datum/ai_behavior/metroid_evolve/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/metroid/juvenile)

/datum/ai_behavior/metroid_evolve/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/metroid/juvenile/MJ = brain.holder
	if(!istype(MJ))
		return null
	if(MJ.nutrition < MJ.evo_point)
		return null
	return DQAI_RESULT(2, MJ)

/datum/ai_behavior/metroid_evolve/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/metroid/juvenile/MJ = brain.holder
	if(!istype(MJ))
		return DQ_BEHAVIOR_FAILED
	// evolve() re-checks nutrition / buckled / vore state and handles the queen
	// egg-laying path itself.
	MJ.evolve()
	return DQ_BEHAVIOR_DONE
