// Gryphon port — restores the "lone-prey stalking ramp" AI that lived on the
// deleted /datum/ai_holder/simple_mob/vore/gryphon subtype.
//
// The legacy gryphon was a patient ambush predator. Its find_target() override
// refused to commit unless its quarry was ALONE: while a single sentient,
// edible player lingered in view with no other targets, it ran possibly_eat(),
// a counter (eat_attempts) that:
//   * at 5  attempts: "\The gryphon licks its beak"
//   * at 10 attempts: "\The gryphon's stomach grumbles loudly"
//   * after 15, while still alone: actually gives_target() and pounces.
// The moment a second target appeared, the ramp reset (it won't eat in company).
// A separate do_special_attack() leap (still on the mob) closed the gap.
//
// Modern port: the ramp is one BACKGROUND behavior whose evaluate() reproduces
// find_target()'s "exactly one lonely edible sentient" gate and ticks the
// counter, only promoting the victim to primary_threat once the ramp matures.
// Counter state (eat_attempts + the victim ref) lives on the mob. The leap
// becomes an OVERRIDE behavior that calls the surviving special_attack pipeline.

/mob/living/simple_mob/vore/gryphon
	// Ambush predator: doesn't aggro the room on sight; it stalks a lone meal.
	ai_attack_on_sight = FALSE
	/// Stalking ramp counter — climbs while a lone edible player lingers.
	var/dq_eat_attempts = 0
	/// Weakref to the player the gryphon is currently fixating on.
	var/datum/weakref/dq_maybe_eating = null

/mob/living/simple_mob/vore/gryphon/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/gryphon_stalk,
		/datum/ai_behavior/gryphon_leap,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// ---------------------------------------------------------------------------
// Shared helper — is M a valid lone-meal candidate? (edible + sentient).
// ---------------------------------------------------------------------------

/// Edible-prey check mirroring the legacy ai_holder vore_check(): inits vore if
/// needed, then validates the mob is a living, devourable, mob-vore-permitting
/// target we have a belly for.
/mob/living/simple_mob/proc/dq_vore_check(mob/living/L)
	if(!voremob_loaded)
		init_vore(TRUE)
	if(!vore_selected)
		return FALSE
	if(!isliving(L))
		return FALSE
	if(!L.devourable || !L.allowmobvore)
		return FALSE
	return TRUE

// ---------------------------------------------------------------------------
// 1. Stalk ramp — the bespoke lone-prey fixation. Only ever runs when exactly
//    one edible, client-controlled, attackable target is around; matures into a
//    real attack after enough patient buildup.
// ---------------------------------------------------------------------------

/datum/ai_behavior/gryphon_stalk
	name = "gryphon stalk"
	// BACKGROUND + no_threat_required so it only operates while the gryphon has
	// no real fight on its hands; the instant a second target shows up the ramp
	// resets and normal behaviors take over.
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_MOB
	no_threat_required = TRUE

/datum/ai_behavior/gryphon_stalk/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/gryphon)

/datum/ai_behavior/gryphon_stalk/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/gryphon/G = brain.get_owner()
	if(!istype(G) || G.client)
		return null
	if(!brain.model)
		return null
	// Already committed to a fight — let the combat kit handle it.
	if(brain.primary_threat)
		dq_gryphon_reset_ramp(G)
		return null
	// Find a single lonely, edible, sentient candidate. If more than one
	// attackable target is present, the gryphon won't eat in company.
	var/mob/living/sentient = null
	var/alone = TRUE
	for(var/mob/living/M as anything in brain.model.visible_hostiles)
		if(M.client)
			if(isnull(sentient) && G.dq_vore_check(M))
				sentient = M
			else
				alone = FALSE
		else
			// A non-player target also counts as company that spoils the stalk.
			alone = FALSE
	if(!sentient || !alone)
		dq_gryphon_reset_ramp(G)
		return null
	return DQAI_RESULT(2, sentient)

/datum/ai_behavior/gryphon_stalk/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/gryphon/G = brain.get_owner()
	var/mob/living/victim = target
	if(!istype(G) || !istype(victim))
		return DQ_BEHAVIOR_FAILED
	// Recompute "alone" — was true at evaluate; recheck so the ramp respects a
	// crowd that arrived between ticks.
	var/alone = dq_gryphon_alone_with(brain, G, victim)
	// New victim resets the counter (legacy: target != maybe_eating).
	var/mob/old_victim = G.dq_maybe_eating?.resolve()
	if(victim != old_victim)
		G.dq_eat_attempts = 0
	G.dq_maybe_eating = WEAKREF(victim)
	// Teasing messages at the legacy thresholds.
	if(G.dq_eat_attempts == 5)
		to_chat(victim, span_danger("\The [G] licks its beak"))
	else if(G.dq_eat_attempts == 10)
		to_chat(victim, span_danger("\The [G]'s stomach grumbles loudly"))
	else if(alone && G.dq_eat_attempts > 15)
		// Ramp matured while alone — commit. give_target() promotes the victim
		// to a hostile primary_threat so the leap / melee kit takes the kill.
		brain.give_target(victim, TRUE)
		dq_gryphon_reset_ramp(G)
		return DQ_BEHAVIOR_DONE
	// Keep climbing while still building (or while alone past the cap).
	if(G.dq_eat_attempts < 11 || alone)
		G.dq_eat_attempts += 1
	return DQ_BEHAVIOR_DONE

/// Reset the stalking ramp.
/proc/dq_gryphon_reset_ramp(mob/living/simple_mob/vore/gryphon/G)
	if(!istype(G))
		return
	G.dq_eat_attempts = 0
	G.dq_maybe_eating = null

/// True if `victim` is the only attackable target the gryphon can see.
/proc/dq_gryphon_alone_with(datum/ai_brain/brain, mob/living/simple_mob/vore/gryphon/G, mob/living/victim)
	if(!brain.model)
		return TRUE
	for(var/mob/living/M as anything in brain.model.visible_hostiles)
		if(M != victim)
			return FALSE
	return TRUE

// ---------------------------------------------------------------------------
// 2. Leap — the telegraphed pounce gap-closer. Wraps the surviving
//    do_special_attack() / special_attack_target() pipeline on the mob.
// ---------------------------------------------------------------------------

/datum/ai_behavior/gryphon_leap
	name = "gryphon leap"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	blocks_reselection = TRUE
	min_range = 2
	max_range = 4

/datum/ai_behavior/gryphon_leap/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/gryphon)

/datum/ai_behavior/gryphon_leap/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/gryphon/G = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!istype(G) || !isliving(threat))
		return null
	if(!G.can_special_attack(threat))
		return null
	return DQAI_RESULT(75, threat)

/datum/ai_behavior/gryphon_leap/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/simple_mob/vore/gryphon/G = brain.get_owner()
	if(!istype(G) || !isliving(target))
		return DQ_BEHAVIOR_FAILED
	// special_attack_target() sets last_special_attack and runs do_special_attack
	// (the leap, which is async via `set waitfor = FALSE` and toggles ai_brain.busy
	// itself). We just kick it off.
	G.special_attack_target(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/gryphon_leap/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Leap",
		"desc" = "Pounce at a nearby target to knock them down.",
		"category" = "Combat",
		"auto_target" = FALSE,
	)
	return L
