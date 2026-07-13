// Blaidd port — restores the "stalking predator that won't be watched"
// behavior from the deleted /datum/ai_holder/simple_mob/vore/blaidd.
//
// Legacy flavor, faithfully reconstructed:
//   * A wolf that rushes prey from off-screen (vision_range 12) but freezes
//     and ultimately flees the moment its prey LOOKS at it. The old
//     check_witness() used dir math: a target counts as "watching" the blaidd
//     if the blaidd sits in the half-plane the target is facing. It first set
//     STANCE_IDLE (stop approaching), and if the staring persisted ~0.5s it
//     stepped away.
//   * Active camouflage: cloaks while pursuing at range, uncloaks adjacent.
//     The mob already owns blaidd_invisibility + update_icon for the sprite;
//     this port drives the toggle that the legacy set_invis() handled.
//   * Vore targeting falls out of the generic melee path: simple_mob's
//     apply_attack already pounces + EatTargets edible prey on a melee hit, so
//     /datum/ai_behavior/melee_attack swallows prey with no bespoke behavior.
//
// The witness rule is the showpiece. It's split in two so it can both *stop
// approaching* (a high-priority gate that beats approach_threat) and *flee*
// (an INTERRUPT that fires once the stare persists). State (when the stare
// started) lives on the mob, not the flyweight behavior.

/mob/living/simple_mob/vore/blaidd
	/// world.time the current uninterrupted stare-down began; 0 if not watched.
	var/blaidd_watched_since = 0

/mob/living/simple_mob/vore/blaidd/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/blaidd_flee_watched,
		/datum/ai_behavior/blaidd_freeze_watched,
		/datum/ai_behavior/blaidd_stealth,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/investigate_noise,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// Blaidd prefers to hunt clients, like the legacy vore predator.
/mob/living/simple_mob/vore/blaidd/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/prefer_players,
		/datum/target_selector/closest,
	)
	return L

// ---------------------------------------------------------------------------
// Witness math — shared helper.
// ---------------------------------------------------------------------------

/// TRUE if `watcher` is facing `subject` (the blaidd is inside the half-plane
/// the watcher is looking toward). Reproduces the legacy check_witness() dir test.
/proc/dq_blaidd_is_watched_by(mob/living/subject, mob/living/watcher)
	if(!subject || !watcher)
		return FALSE
	switch(watcher.dir)
		if(NORTH) return subject.y >= watcher.y
		if(SOUTH) return subject.y <= watcher.y
		if(EAST)  return subject.x >= watcher.x
		if(WEST)  return subject.x <= watcher.x
	return FALSE

/// Returns a live, conscious hostile within 9 tiles who is currently watching
/// the blaidd AND hasn't attacked it (legacy: !check_attacker && !stat). If the
/// prey is incapacitated, the blaidd ignores the stare and keeps hunting.
/proc/dq_blaidd_active_watcher(datum/ai_brain/brain)
	if(!brain || !brain.model)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	for(var/mob/living/L as anything in brain.model.visible_hostiles)
		if(L.stat)
			continue
		if(brain.check_attacker(L))
			continue  // they hit us first; no longer shy of them
		if(get_dist(owner, L) > 9)
			continue
		if(dq_blaidd_is_watched_by(owner, L))
			return L
	return null

// ---------------------------------------------------------------------------
// Freeze when watched — stop closing the distance while a target stares.
// Higher priority than approach_threat so it pre-empts pursuit, but only an
// OVERRIDE (not INTERRUPT) so the flee behavior can still escalate past it.
// ---------------------------------------------------------------------------

/datum/ai_behavior/blaidd_freeze_watched
	name = "freeze (watched)"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	no_threat_required = FALSE

/datum/ai_behavior/blaidd_freeze_watched/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/blaidd)

/datum/ai_behavior/blaidd_freeze_watched/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	// If already adjacent we should be attacking, not freezing — let melee win.
	if(brain.primary_threat && owner.Adjacent(brain.primary_threat))
		return null
	var/mob/living/watcher = dq_blaidd_active_watcher(brain)
	if(!watcher)
		return null
	// Beats approach_threat (10) but loses to a melee attack opportunity.
	return DQAI_RESULT(35, watcher)

/datum/ai_behavior/blaidd_freeze_watched/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(owner && target)
		owner.face_atom(target)
	// Hold still. Do nothing else — re-evaluated each tick.
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Flee when watched — once a stare has persisted ~0.5s, break off and run.
// INTERRUPT so it can override the freeze. Mirrors the legacy spawn(5) escalation.
// ---------------------------------------------------------------------------

/datum/ai_behavior/blaidd_flee_watched
	name = "flee (watched)"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	/// How long an unbroken stare must persist before the blaidd bolts.
	var/stare_grace = 5  // deciseconds, matching legacy spawn(5)
	/// How far it tries to put between itself and the watcher.
	var/flee_distance = 8

/datum/ai_behavior/blaidd_flee_watched/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/blaidd)

/datum/ai_behavior/blaidd_flee_watched/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/blaidd/B = brain.holder
	if(!istype(B))
		return null
	// Adjacent prey is fair game — pounce, don't flee. Legacy let can_attack
	// through at distance <= 2.
	if(brain.primary_threat && B.Adjacent(brain.primary_threat))
		B.blaidd_watched_since = 0
		return null
	var/mob/living/watcher = dq_blaidd_active_watcher(brain)
	if(!watcher)
		B.blaidd_watched_since = 0
		return null
	// First tick of a stare: start the grace timer, don't flee yet (freeze instead).
	if(!B.blaidd_watched_since)
		B.blaidd_watched_since = world.time
		return null
	if(world.time < B.blaidd_watched_since + stare_grace)
		return null
	return DQAI_RESULT(90, watcher)

/datum/ai_behavior/blaidd_flee_watched/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target)
		return DQ_BEHAVIOR_FAILED
	step_away(owner, target, flee_distance)
	owner.face_atom(target)
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/blaidd_flee_watched/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/blaidd/B = brain.holder
	if(!istype(B) || !target)
		return DQ_BEHAVIOR_FAILED
	// Stop fleeing once we've broken line-of-stare or opened up distance.
	if(get_dist(B, target) >= flee_distance || !dq_blaidd_active_watcher(brain))
		B.blaidd_watched_since = 0
		return DQ_BEHAVIOR_DONE
	step_away(B, target, brain.vision_range)
	B.face_atom(target)
	return DQ_BEHAVIOR_CONTINUE

// ---------------------------------------------------------------------------
// Active camouflage — cloak while stalking at range, uncloak adjacent.
// Background priority so it never competes with combat; just keeps the
// blaidd_invisibility flag (and thus the sprite) in sync with the chase, the
// way the legacy set_invis()/handle_stance_strategical did each strategic tick.
// ---------------------------------------------------------------------------

/datum/ai_behavior/blaidd_stealth
	name = "active camouflage"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE

/datum/ai_behavior/blaidd_stealth/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/blaidd)

/datum/ai_behavior/blaidd_stealth/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/blaidd/B = brain.holder
	if(!istype(B) || B.stat == DEAD || B.client)
		return null
	return DQAI_RESULT(2, B)

/datum/ai_behavior/blaidd_stealth/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/blaidd/B = brain.holder
	if(!istype(B))
		return DQ_BEHAVIOR_DONE
	// No prey in view, or adjacent to prey -> drop the cloak. Otherwise hide.
	var/mob/threat = brain.primary_threat
	var/want_cloak = FALSE
	if(threat && get_dist(B, threat) > 1)
		want_cloak = TRUE
	if(want_cloak && !B.blaidd_invisibility)
		B.blaidd_invisibility = 1
		B.update_icon()
	else if(!want_cloak && B.blaidd_invisibility)
		B.blaidd_invisibility = 0
		B.update_icon()
	return DQ_BEHAVIOR_DONE
