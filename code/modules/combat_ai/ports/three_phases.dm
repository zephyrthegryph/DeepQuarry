// Modern-AI port for /mob/living/simple_mob/mechanical/mecha/eclipse —
// the "three phases" bullet-hell boss.
//
// Legacy AI: /datum/ai_holder/simple_mob/intentional/three_phases.
//   - on_engagement(): kept its distance from the target, stepping closer only
//     when farther than closest_desired_distance (6 tiles). It is a ranged
//     bullet-hell mob and wants to keep a kiting distance.
//   - pre_special_attack(): a phase machine that set a_intent purely off the
//     boss's HP fraction:  <=0.35 -> DISARM (phase 3), <=0.7 -> GRAB (phase 2),
//     else HURT (phase 1).  The base eclipse's do_special_attack() runs the
//     same bullet_heck(A, 3, 3) regardless of intent, so the intent is a
//     flavor/telegraph hook the subtypes (battle_top / ufo / janus) override.
//     We faithfully reproduce the a_intent phase-set so any subtype that keys
//     off a_intent in its do_special_attack still phases correctly.
//
// The boss fires its special almost constantly (special_attack_cooldown = 10),
// so the special-attack behavior is the centerpiece; melee is a fallback for
// when something is right next to it.
//
// The /no_movement variant (turret hivebots) is handled by zeroing the kite
// behavior's applicability — those mobs simply never reposition.

/mob/living/simple_mob/mechanical/mecha/eclipse
	use_modern_ai = TRUE

/mob/living/simple_mob/mechanical/mecha/eclipse/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/three_phases_special,
		/datum/ai_behavior/three_phases_kite,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/mechanical/mecha/eclipse/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/prefer_players,
		/datum/target_selector/closest,
	)
	return L

// ---------------------------------------------------------------------------
// Phase machine + bullet-hell special attack.
//
// One behavior maps the legacy "pre_special_attack picks a_intent by phase,
// then do_special_attack() fires" loop. It gates on can_special_attack /
// should_special_attack (the mob's own range + cooldown logic via the legacy
// shim) and sets the phase intent before firing.
// ---------------------------------------------------------------------------

/datum/ai_behavior/three_phases_special
	name = "bullet-hell barrage"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB

/datum/ai_behavior/three_phases_special/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/mechanical/mecha/eclipse)

/datum/ai_behavior/three_phases_special/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/mechanical/mecha/eclipse/E = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(E) || !threat)
		return null
	// Mob-side range + cooldown + should_special_attack gating (legacy shim).
	if(!E.can_special_attack(threat))
		return null
	return DQAI_RESULT(75, threat)

/datum/ai_behavior/three_phases_special/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/mechanical/mecha/eclipse/E = brain.holder
	if(!istype(E) || !isliving(target))
		return DQ_BEHAVIOR_FAILED
	// Phase machine: pick the telegraph intent from the boss's HP fraction,
	// exactly as legacy pre_special_attack() did.
	var/hp_frac = E.health / E.getMaxHealth()
	if(hp_frac <= 0.35)
		E.a_intent = I_DISARM   // Phase three
	else if(hp_frac <= 0.7)
		E.a_intent = I_GRAB     // Phase two
	else
		E.a_intent = I_HURT     // Phase one
	E.special_attack_target(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Kite — maintain the legacy closest_desired_distance of 6 tiles. When the
// target closes inside that range, step away; bullet-hell wants breathing room.
// ---------------------------------------------------------------------------

/datum/ai_behavior/three_phases_kite
	name = "keep distance"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	/// Mirrors legacy closest_desired_distance.
	var/desired_distance = 6

/datum/ai_behavior/three_phases_kite/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob/mechanical/mecha/eclipse))
		return FALSE
	// Anchored turret hivebots (the legacy /no_movement variant) never reposition.
	return !owner.anchored

/datum/ai_behavior/three_phases_kite/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat)
		return null
	if(get_dist(owner, threat) >= desired_distance)
		return null
	// Score above approach_threat (10) so it wins when the target is too close,
	// but below the special attack so it never preempts a ready barrage.
	return DQAI_RESULT(20, threat)

/datum/ai_behavior/three_phases_kite/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	if(get_dist(owner, target) >= desired_distance)
		return DQ_BEHAVIOR_DONE
	var/turf/away = get_step_away(owner, target)
	if(away && !away.density)
		owner.IMove(away)
	return DQ_BEHAVIOR_CONTINUE
