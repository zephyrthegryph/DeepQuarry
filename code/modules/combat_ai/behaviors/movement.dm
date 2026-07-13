// Movement behaviors. None of these deal damage; they reposition the mob.

/// Deciseconds an AI mob waits between steps: the natural per-step interval (the larger of
/// the fast-tick cadence or the mob's own movement_delay) scaled by DQ_AI_MOVE_DELAY_MULT, so
/// mobs move at a clear fraction of a running player's pace — the player outpaces a swarm and
/// can kite it, and detection stays noise-led. The mob's move cooldown (next_move) is gated on this.
/proc/dq_ai_move_delay(mob/living/owner)
	return max(SSaifast.wait, owner.movement_delay()) * DQ_AI_MOVE_DELAY_MULT

/// Glide a stepped tile across one AI move interval so movement animates smoothly
/// instead of snapping. An AI step_to() defaults glide_size, which leaves the icon
/// to teleport; matching the glide to dq_ai_move_delay makes it slide like a walk.
/// Re-applied before each AI step.
/proc/dq_set_move_glide(mob/living/owner)
	if(owner)
		owner.glide_size = WORLD_ICON_SIZE / max(DS2TICKS(dq_ai_move_delay(owner)), 1)

/// One throttled step toward `goal`, honoring the AI move cooldown so ALL AI
/// repositioning — retreats, kites, flanks — moves at the same measured half-tick pace
/// as an approach, never a full-tick-rate sprint. Glides smoothly. Returns TRUE if it
/// stepped. Every away-from-the-player behavior routes movement through here so fleeing
/// looks as deliberate as closing in.
/proc/dq_ai_step_to(mob/living/owner, atom/goal)
	if(!owner || !goal)
		return FALSE
	if(world.time < owner.next_move)
		return FALSE
	dq_set_move_glide(owner)
	var/turf/before = get_turf(owner)
	step_to(owner, goal)
	if(get_turf(owner) == before)
		return FALSE
	owner.setMoveCooldown(dq_ai_move_delay(owner))
	return TRUE

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
	// Throttle to the AI move rate: hold until the mob is off its move cooldown so it
	// moves at ~half the tick rate (the player can outrun a swarm) rather than every
	// 250ms. The tactical tick still runs; it just doesn't step every time.
	if(world.time < owner.next_move)
		return DQ_BEHAVIOR_CONTINUE
	// Pack pincer: a flanker the lord gave a slot heads for the tile on its assigned side
	// of the target instead of straight at it, so the pack surrounds the target rather
	// than stacking onto one face. Once adjacent to the real target (above) it attacks;
	// if the slot tile is blocked we just fall back to closing on the target.
	var/atom/move_goal = target
	if(brain.flank_dir && brain.pack_role == DQ_ROLE_FLANKER)
		var/turf/slot = get_step(get_turf(target), brain.flank_dir)
		// Only take the flank slot if it's on our approach side — never if reaching it means
		// walking AROUND the target (a slot farther from us than the target is behind it), which
		// reads as the mob "running away" mid-fight. Otherwise just close straight in.
		if(slot && !slot.density && !owner.Adjacent(slot) && get_dist(owner, slot) <= get_dist(owner, target))
			move_goal = slot
	// One step per move interval, glided across it so it slides smoothly instead of
	// teleporting. step_to() handles open ground and minor obstacles cheaply; the A*
	// pather only blocks when the pathfinder is free (non-blocking). A wall-slide
	// covers cave corners and side-by-side packmates so the swarm flows.
	dq_set_move_glide(owner)
	var/turf/before = get_turf(owner)
	step_to(owner, move_goal)
	var/moved = (get_turf(owner) != before)
	if(!moved)
		moved = dq_corner_step(owner, move_goal)
	if(!moved)
		brain.smart_step_toward(move_goal) // genuinely walled in — path around it (non-blocking; may skip this tick)
		moved = (get_turf(owner) != before)
	if(moved)
		owner.setMoveCooldown(dq_ai_move_delay(owner)) // start the move cooldown
		brain.failed_steps = 0
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
	// Throttle to the AI move pace: an idle mob that's still on the fast tick for some other
	// reason must not skitter a step every 250ms. Wander a good bit slower than a pursuit, too.
	if(world.time < owner.next_move)
		return DQ_BEHAVIOR_DONE
	if(prob(35))
		var/turf/T = get_step(owner, pick(GLOB.cardinal))
		if(T && !T.density)
			dq_set_move_glide(owner)
			step_to(owner, T)
			owner.setMoveCooldown(dq_ai_move_delay(owner) * 2) // leisurely amble, slower than chasing
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
#if DQ_AI_RETREAT_DISABLED
	return null // wounded mobs fight on instead of fleeing
#else
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
#endif

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
		dq_ai_step_to(owner, away) // throttled — fleeing moves at the same pace as approaching
	return DQ_BEHAVIOR_CONTINUE
