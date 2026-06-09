// Noise system.
//
// Loud actions in a quarry layer alert nearby hostile mobs and bump
// the layer's danger level. The same call does both: noise has two
// consequences, never one without the other. This makes "be loud" a
// real choice — pickaxe spam draws aggro AND ramps the danger meter.
//
// Sources call SSquarry.emit_noise(origin, loudness, source = null):
//   origin  : turf the noise comes from
//   loudness: integer, used as both the alert radius (tiles) and the
//             danger bump (divided by a tunable factor)
//   source  : optional atom that caused it, for log clarity
//
// Mobs in the radius that are currently idle / sleeping are given
// origin as a wander destination so they investigate. Mobs already
// in combat are left alone — they have a real target, no need to
// redirect them.
//
// Noise events don't cross z-levels: only mobs on origin.z are
// affected, and only the layer at origin.z gets the danger bump.

#define QUARRY_NOISE_DANGER_DIVISOR 8  // danger bump = round(loudness / divisor)

// Loudness presets (QUARRY_NOISE_*) live in quarry_defines.dm so the
// goal-hook procs in quarry_goal_hooks.dm can reference them at
// parse time.


/datum/controller/subsystem/quarry/proc/emit_noise(turf/origin, loudness, atom/source = null)
	if(!isturf(origin) || !isnum(loudness) || loudness <= 0)
		return
	var/datum/quarry_layer/L = layer_at_z(origin.z)
	if(!L)
		// Not a quarry z. Noise is a no-op outside the mine.
		return

	// (B) Aggregate danger bump. Sub-1 contributions still round to 0
	// for small noise; that's fine — only meaningful actions move the
	// danger meter.
	var/danger_bump = round(loudness / QUARRY_NOISE_DANGER_DIVISOR)
	if(danger_bump > 0)
		add_layer_danger(L, danger_bump)

	// (A) Alert hostile mobs in the radius to investigate. We walk
	// the layer's mob list rather than the world — cheap, since each
	// layer has at most a few dozen hostiles. Skip mobs that are
	// already engaged with a target.
	for(var/mob/living/simple_mob/M in GLOB.living_mob_list)
		if(M.z != origin.z)
			continue
		if(M.stat == DEAD)
			continue
		if(get_dist(M, origin) > loudness)
			continue
		if(!M.ai_holder)
			continue
		// Already fighting / approaching something — don't redirect.
		// Idle, sleeping, alert, and follow-state mobs can re-task.
		var/stance = M.ai_holder.stance
		if(stance == STANCE_APPROACH || stance == STANCE_FIGHT \
			|| stance == STANCE_BLINDFIGHT || stance == STANCE_ATTACK \
			|| stance == STANCE_ATTACKING)
			continue
		// give_destination just sets the AI's wander target; the
		// mob's own AI tick handles actually moving. Stays alert
		// behavior + acquire_target will fire if it walks within
		// line of sight of a player en route.
		if(M.ai_holder.stance == STANCE_SLEEP)
			M.ai_holder.set_stance(STANCE_IDLE)
		M.ai_holder.give_destination(origin, 1)
