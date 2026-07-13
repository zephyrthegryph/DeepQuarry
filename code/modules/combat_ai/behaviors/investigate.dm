// Investigate-noise behavior.
//
// When a loud sound goes off near a simple_mob that isn't already fighting,
// the mob walks to the source to check it out, peers around, then resumes
// idling. Loud playsound() calls fan out to nearby brains via
// dq_ai_propagate_noise(), which calls notify_noise() on each — that records
// the source turf and fires COMSIG_DQAI_HEARD_HAZARD so this behavior wakes.
//
// In-combat mobs ignore noise (they already have a target). A hostile mob that
// hears combat and walks over will naturally engage once it sees a target, so
// loud fights pull in nearby reinforcements.

/datum/ai_brain
	/// Turf of the loud noise the mob is currently investigating (+ expiry).
	var/turf/noise_turf = null
	var/noise_expiry = 0

/// Records a heard noise and wakes the investigate behavior. No-op while in
/// combat, busy, dead/unconscious, or player-piloted.
/datum/ai_brain/proc/notify_noise(turf/T)
	if(!T || primary_threat || busy)
		return
	if(QDELETED(holder) || holder.stat != CONSCIOUS || holder.client)
		return
	noise_turf = T
	noise_expiry = world.time + DQ_NOISE_INVESTIGATE_TTL
	dispatch_behavior_signal(COMSIG_DQAI_HEARD_HAZARD, T)

/// Fan a loud noise out to nearby AI simple_mobs so they investigate. Called
/// from the playsound() hook for sufficiently loud, non-global sounds. Louder
/// sounds carry farther (capped). Mobs already in combat are skipped cheaply.
/proc/dq_ai_propagate_noise(atom/source, turf/origin, loudness)
	if(!origin)
		return
	var/r = clamp(round(loudness / 8), 4, 8)
	for(var/mob/living/simple_mob/SM in range(r, origin))
		if(SM == source || SM.client || SM.stat != CONSCIOUS)
			continue
		var/datum/ai_brain/B = SM.ai_brain
		if(!B || B.primary_threat)
			continue
		B.notify_noise(origin)

/datum/ai_behavior/investigate_noise
	name = "investigate noise"
	priority_class = DQ_BEHAVIOR_PRIORITY_IDLE
	target_kind = DQ_TARGET_TURF
	no_threat_required = TRUE
	eval_triggers = list(COMSIG_DQAI_HEARD_HAZARD)

/datum/ai_behavior/investigate_noise/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob)

/datum/ai_behavior/investigate_noise/on_signal(datum/ai_brain/brain, sig_type, turf/T)
	if(T)
		brain.noise_turf = T
		brain.noise_expiry = world.time + DQ_NOISE_INVESTIGATE_TTL
	brain.invalidate_selection()

/datum/ai_behavior/investigate_noise/evaluate(datum/ai_brain/brain, atom/source)
	if(brain.primary_threat)              // combat always wins; drop the lead
		brain.noise_turf = null
		return null
	var/turf/T = brain.noise_turf
	if(!T || world.time > brain.noise_expiry)
		brain.noise_turf = null
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner || get_dist(owner, T) <= 0)
		brain.noise_turf = null
		return null
	// IDLE class, but well above idle_wander so a heard noise wins over roaming.
	return DQAI_RESULT(40, T)

/datum/ai_behavior/investigate_noise/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.holder
	if(!owner || !target || brain.primary_threat || world.time > brain.noise_expiry)
		brain.noise_turf = null
		return DQ_BEHAVIOR_DONE
	if(get_dist(owner, target) <= 1)
		owner.face_atom(target)        // arrived — peer around, then resume idling
		brain.noise_turf = null
		return DQ_BEHAVIOR_DONE
	if(!brain.smart_step_toward(target, 1))
		step_to(owner, target)
	return DQ_BEHAVIOR_CONTINUE
