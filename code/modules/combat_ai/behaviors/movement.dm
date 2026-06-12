// Movement behaviors. None of these deal damage; they reposition the mob.

// A chaser takes up to this many steps per 250ms tactical tick while still far
// from its target, so it keeps pace with a running player instead of falling
// behind at one-step-per-tick. Within APPROACH_SMOOTH_DIST it drops to a single
// step per tick so close-quarters movement doesn't blink.
#define APPROACH_MAX_STEPS_PER_TICK 2
#define APPROACH_SMOOTH_DIST 2

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
	// Cheap built-in step first. step_to() handles open ground and minor obstacles
	// synchronously; the A* pather (smart_step_toward) blocks the tick on stoplag
	// while SSpathfinder runs, and a moving target forces constant recomputes — so
	// leading with A* made the mob barely move. Only fall back to A* when step_to
	// can't make progress (a wall/maze between us). Take a second step while still
	// far so a chaser keeps pace with a running player.
	var/moved = FALSE
	for(var/i in 1 to APPROACH_MAX_STEPS_PER_TICK)
		if(owner.Adjacent(target))
			break
		var/turf/before = get_turf(owner)
		step_to(owner, target)
		if(get_turf(owner) == before)
			break // blocked — try to path around below
		moved = TRUE
		brain.failed_steps = 0
		if(get_dist(owner, target) <= APPROACH_SMOOTH_DIST)
			break // close now; one step/tick from here keeps it smooth
	if(!moved)
		brain.smart_step_toward(target) // genuinely walled in — path around it
	return DQ_BEHAVIOR_CONTINUE

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
