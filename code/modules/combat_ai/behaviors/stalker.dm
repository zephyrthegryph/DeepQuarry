// Stalker behaviors — an ambush predator that doesn't brawl. It keeps its distance and
// circles its prey, staying just out of reach, and only COMMITS to the kill when the prey
// is weakened (low HP, gassed, staggered, or downed) or ALONE (no ally nearby). While it's
// stalking, stalk_orbit out-scores plain approach so the mob holds the band and strafes;
// the instant the commit condition trips, stalk_orbit bows out and the dash/melee kit takes
// over and rushes in. Add to a mob via get_ai_behaviors().

/// TRUE when the prey is vulnerable enough that a stalker should drop the cat-and-mouse and
/// go for the kill: worn down (low HP/stamina, staggered, or on the ground) or isolated.
/proc/dq_stalker_should_commit(mob/living/owner, mob/living/threat)
	if(!isliving(threat) || threat.stat >= DEAD)
		return FALSE
	if(threat.is_stagger_broken() || threat.lying || threat.weakened)
		return TRUE
	if(threat.maxHealth && threat.health / threat.maxHealth <= DQ_STALK_COMMIT_HP)
		return TRUE
	if(dq_prey_exhausted(threat)) // low stamina / collapsed (proc lives in predation.dm)
		return TRUE
	return dq_target_is_isolated(owner, threat)

/// TRUE when `threat` has STRAYED from its group — there are other players on the layer but
/// none of them near the prey. A genuinely solo player (the only one on the layer) is NOT
/// "isolated": there's no group to wander from, so the stalker keeps circling until they're
/// worn down instead. Cheap: a z-level player count, then one short view() only if a group exists.
/proc/dq_target_is_isolated(mob/living/owner, mob/living/threat)
	var/turf/T = get_turf(threat)
	if(!T)
		return FALSE
	var/list/zplayers = (T.z >= 1 && T.z <= length(GLOB.living_players_by_zlevel)) ? GLOB.living_players_by_zlevel[T.z] : null
	if(LAZYLEN(zplayers) <= 1)
		return FALSE // solo on this layer — stalk until weakened, don't insta-commit
	for(var/mob/living/M in dview(DQ_STALK_LONELY_RANGE, threat)) // dview: lighting-independent, like perception
		if(M == threat || M == owner || M.stat >= DEAD)
			continue
		if(M.client) // a fellow player stands with them — not alone
			return FALSE
	return TRUE // separated from the group → easy pickings

// --- Stalk orbit ------------------------------------------------------------
// The default while NOT committing: hold the preferred band and circle. Out-scores plain
// approach (10) so a stalker maintains range instead of closing; yields entirely once the
// commit condition trips so the rush-in behaviors take over.

/datum/ai_behavior/stalk_orbit
	name = "stalk"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED)

/datum/ai_behavior/stalk_orbit/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob) && !owner.anchored

/datum/ai_behavior/stalk_orbit/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/living/threat = brain.primary_threat
	if(!owner || !isliving(threat))
		return null
	if(dq_stalker_should_commit(owner, threat))
		return null // time to go in for the kill — let approach / pounce / melee run
	// Above approach_threat (10): while stalking, hold the band rather than close in.
	return DQAI_RESULT(18, threat)

/datum/ai_behavior/stalk_orbit/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !isliving(target) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	if(owner.anchored)
		return DQ_BEHAVIOR_FAILED
	owner.face_atom(target)
	if(world.time < owner.next_move) // throttle to the AI move pace
		return DQ_BEHAVIOR_CONTINUE
	var/dist = get_dist(owner, target)
	if(dist < DQ_STALK_RANGE_MIN)
		// Too close — give ground, keeping eyes on the prey.
		var/turf/away = get_step_away(owner, target)
		if(away && !away.density)
			dq_ai_step_to(owner, away)
	else if(dist > DQ_STALK_RANGE_MAX)
		// Drifted too far — close back to the band.
		dq_ai_step_to(owner, target)
	else
		// In the band — circle. Strafe perpendicular (consistent direction → a smooth orbit),
		// falling back to the other side if that step is blocked.
		var/to_target = get_dir(owner, target)
		var/turf/slot = get_step(owner, turn(to_target, 90))
		if(!slot || slot.density)
			slot = get_step(owner, turn(to_target, -90))
		if(slot && !slot.density)
			dq_ai_step_to(owner, slot)
	return DQ_BEHAVIOR_CONTINUE

// --- Stalk pounce -----------------------------------------------------------
// The commit: a telegraphed charge that closes the gap for the kill, but ONLY once the prey
// is weakened or alone. Reuses charge_slam's telegraphed-dash machinery; just gates it.

/datum/ai_behavior/charge_slam/stalk_pounce
	name = "stalk pounce"
	cooldown = 6 SECONDS

/datum/ai_behavior/charge_slam/stalk_pounce/evaluate(datum/ai_brain/brain, atom/source)
	if(!dq_stalker_should_commit(brain.get_owner(), brain.primary_threat))
		return null
	return ..()
