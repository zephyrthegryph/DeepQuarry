// Movement behaviors. None of these deal damage; they reposition the mob.

/// Glide a stepped tile across one fast tactical tick so AI movement animates
/// smoothly instead of snapping. An AI step_to() defaults glide_size, which leaves
/// the icon to teleport between tiles; matching the glide to the step cadence
/// (one tile per SSaifast tick) makes it slide like a player walking. Re-applied
/// before each AI step.
/proc/dq_set_move_glide(mob/living/owner)
	if(owner)
		owner.glide_size = WORLD_ICON_SIZE / max(DS2TICKS(SSaifast.wait), 1)

// --- Approach ----------------------------------------------------------------
// Walk toward primary_threat until adjacent. Always available when there's a
// threat we can't yet attack. Scored low so any attack behavior preempts it.

/datum/ai_behavior/approach_threat
	name = "approach"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED)
	cooldown = 0

/datum/ai_behavior/approach_threat/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	if(owner.Adjacent(threat))
		return null  // already in range; let melee_attack pick instead
	return DQAI_RESULT(10, threat)

/datum/ai_behavior/approach_threat/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/approach_threat/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	if(owner.anchored)
		return DQ_BEHAVIOR_FAILED // can't close the distance while anchored; let melee_attack handle adjacency
	if(owner.Adjacent(target))
		brain.clear_path()
		return DQ_BEHAVIOR_DONE
	// One step per tactical tick, glided across the tick so it slides smoothly
	// instead of teleporting (two steps in a single tick read as a snap). step_to()
	// handles open ground and minor obstacles cheaply; the A* pather only blocks the
	// tick when the pathfinder is free (non-blocking), so leading with step_to keeps
	// mobs moving and the swarm un-serialized.
	dq_set_move_glide(owner)
	var/turf/before = get_turf(owner)
	step_to(owner, target)
	if(get_turf(owner) != before)
		brain.failed_steps = 0
		return DQ_BEHAVIOR_CONTINUE
	// Blocked: try a cheap wall-slide (step along one axis toward the target) before
	// reaching for A*. Most cave corners — and packmates side-by-side — clear this
	// way, so the global pathfinder stays idle and mobs don't queue up on it.
	if(dq_corner_step(owner, target))
		return DQ_BEHAVIOR_CONTINUE
	brain.smart_step_toward(target) // genuinely walled in — path around it (non-blocking; may skip this tick)
	return DQ_BEHAVIOR_CONTINUE

/// Cheap obstacle slip: when a straight step toward `target` is blocked, try the
/// nearby directions so a mob can slide around a wall corner OR a packmate standing
/// directly in its way, instead of stalling and demanding an A* path. Tries the two
/// directions 45° off the target heading first (still closing in), then the two
/// perpendicular ones (pure sidestep around a blocker). Non-blocking; returns TRUE
/// if it moved. This is what lets a clustered pack flow toward the player rather
/// than only the front rank advancing.
/proc/dq_corner_step(mob/living/owner, atom/target)
	var/want = get_dir(owner, target)
	for(var/try_dir in list(turn(want, 45), turn(want, -45), turn(want, 90), turn(want, -90)))
		var/turf/before = get_turf(owner)
		step(owner, try_dir)
		if(get_turf(owner) != before)
			return TRUE
	return FALSE

// --- Idle wander -------------------------------------------------------------

/datum/ai_behavior/idle_wander
	name = "wander"
	priority_class = DQ_BEHAVIOR_PRIORITY_IDLE
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE

/datum/ai_behavior/idle_wander/evaluate(datum/ai_brain/brain, atom/source)
	if(brain.primary_threat)
		return null  // not idle if there's a threat
	if(!brain.wander)
		return null  // honor the legacy wander toggle
	return DQAI_RESULT(1, brain.holder)

/datum/ai_behavior/idle_wander/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return DQ_BEHAVIOR_FAILED
	if(owner.anchored)
		return DQ_BEHAVIOR_DONE // anchored: nothing to wander
	if(prob(35))
		var/turf/T = get_step(owner, pick(GLOB.cardinal))
		if(T && !T.density)
			step_to(owner, T)
	return DQ_BEHAVIOR_DONE

// --- Flee at low HP ---------------------------------------------------------
// Runs away from primary_threat. Engages on low HP or when called via signal.

/datum/ai_behavior/flee_low_hp
	name = "flee"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_LOW_HEALTH, COMSIG_DQAI_DAMAGE_TAKEN)
	cooldown = 3 SECONDS

/datum/ai_behavior/flee_low_hp/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !owner.maxHealth)
		return null
	var/hp_frac = owner.health / owner.maxHealth
	if(hp_frac > DQ_LOW_HP_THRESHOLD)
		return null
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	// Score grows as HP drops. At 0% HP and a NEMESIS attacker, this is decisive.
	var/score = (DQ_LOW_HP_THRESHOLD - hp_frac) * 200
	return DQAI_RESULT(score, threat)

/datum/ai_behavior/flee_low_hp/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target)
		return DQ_BEHAVIOR_FAILED
	if(owner.anchored)
		return DQ_BEHAVIOR_FAILED // anchored: can't flee
	if(get_dist(owner, target) >= 8)
		return DQ_BEHAVIOR_DONE  // far enough
	var/turf/away = get_step_away(owner, target)
	if(away && !away.density)
		step_to(owner, away)
	return DQ_BEHAVIOR_CONTINUE
