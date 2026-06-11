// Modern-AI port for /mob/living/simple_mob/vr/alchemistbee.
//
// The legacy version lived on /datum/ai_holder/simple_mob/intentional/alchemistbee
// and worked in two stages:
//   * pre_special_attack(A) picked an a_intent (DISARM/GRAB/HURT) by counting
//     nearby attackable mobs and anchored objects, then do_special_attack()
//     ran a switch keyed on that intent (chemblast / dangerbolt / homingcluster).
//   * on_engagement(A) backpedalled when about to fire an AoE so the bee didn't
//     blow itself up, and otherwise closed to closest_desired_distance.
//
// In the modern framework each special becomes its own OVERRIDE behavior with
// the old "should I pick this?" math folded into evaluate(). The intent switch
// disappears — the brain's scorer picks the most appropriate special directly,
// and each special's cooldown stops it spamming the same one. on_engagement's
// AoE backpedal becomes an INTERRUPT kite behavior. The three special-attack
// procs (chemblast / homingcluster / dangerbolt) stay on the mob unchanged.

// --- Tuning constants ported from the deleted ai_holder ---------------------
// TODO: legacy closest_desired_distance (3) made the bee stop a few tiles short
// of melee; the generic approach_threat closes to adjacency instead. Minor
// behavioral drift — the ranged/special behaviors fire long before adjacency so
// the bee rarely reaches melee anyway.
#define ALCHEMISTBEE_CHEMBLAST_RADIUS         4   // assumed AoE of the vial blast
#define ALCHEMISTBEE_DANGERBOLT_RADIUS        2   // micro-singulo pull radius
#define ALCHEMISTBEE_HOMINGCLUSTER_RADIUS     2   // rocket cluster explosion radius
#define ALCHEMISTBEE_CHEMBLAST_THRESHOLD      3   // nearby attackable mobs to justify chemblast
#define ALCHEMISTBEE_DANGERBOLT_THRESHOLD     1   // net free movables near target for dangerbolt

/mob/living/simple_mob/vr/alchemistbee
	use_modern_ai = TRUE

/mob/living/simple_mob/vr/alchemistbee/initialize_ai_brain()
	. = ..()
	if(. && ai_brain)
		ai_brain.vision_range = 16

/mob/living/simple_mob/vr/alchemistbee/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/alchemistbee_chemblast,
		/datum/ai_behavior/alchemistbee_dangerbolt,
		/datum/ai_behavior/alchemistbee_homingcluster,
		/datum/ai_behavior/alchemistbee_aoe_backpedal,
		/datum/ai_behavior/ranged_attack,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/vr/alchemistbee/get_ai_target_selectors()
	var/static/list/L = list(/datum/target_selector/prefer_players, /datum/target_selector/closest)
	return L

// ---------------------------------------------------------------------------
// Shared helper — count attackable mobs within `radius` of `center`.
// Mirrors the legacy tallies that walked list_targets() with can_attack().
// ---------------------------------------------------------------------------

/proc/dq_alchemistbee_count_near(datum/ai_brain/brain, atom/center, radius)
	. = 0
	if(!brain.model || !center)
		return 0
	for(var/mob/living/M as anything in brain.model.visible_hostiles)
		if(get_dist(center, M) > radius)
			continue
		. += 1

// ---------------------------------------------------------------------------
// 1. Chemblast (legacy I_DISARM) — best when the bee is surrounded, or the
//    target is already inside the blast radius. The old code chose DISARM when
//    chemblast_threshold attackable mobs were within chemblast_radius of the
//    bee, OR the target itself was within that radius.
// ---------------------------------------------------------------------------

/datum/ai_behavior/alchemistbee_chemblast
	name = "alchemist vial blast"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 10 SECONDS
	min_range = 1
	max_range = 14

/datum/ai_behavior/alchemistbee_chemblast/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vr/alchemistbee)

/datum/ai_behavior/alchemistbee_chemblast/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vr/alchemistbee/B = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(B) || !threat)
		return null
	if(!B.can_special_attack(threat))
		return null
	var/surrounded = dq_alchemistbee_count_near(brain, B, ALCHEMISTBEE_CHEMBLAST_RADIUS) >= ALCHEMISTBEE_CHEMBLAST_THRESHOLD
	var/target_in_blast = get_dist(B, threat) <= ALCHEMISTBEE_CHEMBLAST_RADIUS
	if(!surrounded && !target_in_blast)
		return null
	// Surrounded is the strongest case (legacy preferred DISARM first).
	return DQAI_RESULT(surrounded ? 85 : 72, threat)

/datum/ai_behavior/alchemistbee_chemblast/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vr/alchemistbee/B = brain.holder
	if(!istype(B) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	B.last_special_attack = world.time
	B.chemblast(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 2. Dangerbolt (legacy I_GRAB) — the micro-singulo nuke. Old logic: after
//    ruling out chemblast, tally free (non-anchored) attackable movables near
//    the TARGET minus anchored ones; if the net tally meets the threshold,
//    GRAB. Best used to pull a cluster of mobs together.
// ---------------------------------------------------------------------------

/datum/ai_behavior/alchemistbee_dangerbolt
	name = "alchemist dangerbolt"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 10 SECONDS
	min_range = 1
	max_range = 14

/datum/ai_behavior/alchemistbee_dangerbolt/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vr/alchemistbee)

/datum/ai_behavior/alchemistbee_dangerbolt/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vr/alchemistbee/B = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(B) || !threat)
		return null
	if(!B.can_special_attack(threat))
		return null
	// Net "pullable" tally around the target, mirroring the legacy ++/-- logic:
	// free attackable movables increment, anchored ones decrement.
	var/tally = 0
	if(brain.model)
		for(var/mob/living/M as anything in brain.model.visible_hostiles)
			if(get_dist(threat, M) > ALCHEMISTBEE_DANGERBOLT_RADIUS)
				continue
			if(M.anchored)
				tally--
			else
				tally++
	if(tally < ALCHEMISTBEE_DANGERBOLT_THRESHOLD)
		return null
	return DQAI_RESULT(78, threat)

/datum/ai_behavior/alchemistbee_dangerbolt/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vr/alchemistbee/B = brain.holder
	if(!istype(B) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	B.last_special_attack = world.time
	B.dangerbolt(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 3. Homing cluster (legacy I_HURT) — the catch-all rocket barrage. The old
//    code fell back to HURT when neither chemblast nor dangerbolt fit, and for
//    non-living targets when not point-blank. Mid-tier fallback special.
// ---------------------------------------------------------------------------

/datum/ai_behavior/alchemistbee_homingcluster
	name = "alchemist homing cluster"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 10 SECONDS
	min_range = 1
	max_range = 14

/datum/ai_behavior/alchemistbee_homingcluster/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vr/alchemistbee)

/datum/ai_behavior/alchemistbee_homingcluster/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vr/alchemistbee/B = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(B) || !threat)
		return null
	if(!B.can_special_attack(threat))
		return null
	// Always eligible as the fallback special; scored below the situational two
	// so they win when their conditions hold (legacy "else" branch).
	return DQAI_RESULT(60, threat)

/datum/ai_behavior/alchemistbee_homingcluster/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vr/alchemistbee/B = brain.holder
	if(!istype(B) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	B.last_special_attack = world.time
	B.homingcluster(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 4. AoE backpedal — legacy on_engagement made the bee step away when it was
//    about to fire an AoE (homingcluster / dangerbolt) and the target was
//    inside the blast radius, so it wouldn't catch itself in the explosion.
//    Implemented as a short INTERRUPT that fires when a self-endangering AoE
//    special is off cooldown and the target is too close.
// ---------------------------------------------------------------------------

/datum/ai_behavior/alchemistbee_aoe_backpedal
	name = "alchemist backpedal"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED)
	cooldown = 1 SECOND

/datum/ai_behavior/alchemistbee_aoe_backpedal/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vr/alchemistbee)

/datum/ai_behavior/alchemistbee_aoe_backpedal/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vr/alchemistbee/B = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(B) || !threat)
		return null
	var/dist = get_dist(B, threat)
	// Danger range from the legacy switch: blast radius + 3 for either AoE.
	var/danger_range = max(ALCHEMISTBEE_HOMINGCLUSTER_RADIUS, ALCHEMISTBEE_DANGERBOLT_RADIUS) + 3
	if(dist > danger_range)
		return null
	// Only backpedal if an AoE special is actually available to fire soon —
	// otherwise the bee should close the distance, not retreat.
	var/datum/ai_behavior/homing = dq_get_behavior(/datum/ai_behavior/alchemistbee_homingcluster)
	var/datum/ai_behavior/bolt = dq_get_behavior(/datum/ai_behavior/alchemistbee_dangerbolt)
	if(!homing.is_off_cooldown(brain, null) && !bolt.is_off_cooldown(brain, null))
		return null
	return DQAI_RESULT(68, threat)

/datum/ai_behavior/alchemistbee_aoe_backpedal/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	var/danger_range = max(ALCHEMISTBEE_HOMINGCLUSTER_RADIUS, ALCHEMISTBEE_DANGERBOLT_RADIUS) + 3
	var/turf/away = get_step_away(owner, target, danger_range)
	if(away && !away.density)
		step_to(owner, away)
	owner.face_atom(target)
	return DQ_BEHAVIOR_DONE

#undef ALCHEMISTBEE_CHEMBLAST_RADIUS
#undef ALCHEMISTBEE_DANGERBOLT_RADIUS
#undef ALCHEMISTBEE_HOMINGCLUSTER_RADIUS
#undef ALCHEMISTBEE_CHEMBLAST_THRESHOLD
#undef ALCHEMISTBEE_DANGERBOLT_THRESHOLD
