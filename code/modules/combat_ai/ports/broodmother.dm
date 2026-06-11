// Modern-AI port for /mob/living/simple_mob/animal/giant_spider/broodmother.
//
// The legacy /datum/ai_holder/simple_mob/intentional/giant_spider_broodmother
// used pre_special_attack(A) to pick an intent:
//   * I_DISARM (spawn_brood) when 2+ attackable mobs were within 4 tiles, or the
//     target was within 4 tiles — i.e. when enemies are close, birth a swarm
//     right on top of itself.
//   * I_HURT (launch_brood) when the target was more than 4 tiles away — fling
//     broodlings at the distant target.
// do_special_attack() then switched on that intent. should_special_attack()
// gated everything behind can_spawn_brood() (no more than max_brood broodlings
// already in view), and projectiletype gave it a ranged toxin spit as well.
//
// Modern port: spawn_brood and launch_brood each become an OVERRIDE behavior.
// The brood-cap and range gating move into evaluate(); the intent switch is gone
// because the brain scores the situational fit directly. death()'s burst-spawn
// stays on the mob (it's a lifecycle hook, not AI), as do spawn_brood /
// launch_brood / can_spawn_brood.

#define BROODMOTHER_SWARM_RANGE 4   // legacy "enemies are close" radius

/mob/living/simple_mob/animal/giant_spider/broodmother
	use_modern_ai = TRUE

/mob/living/simple_mob/animal/giant_spider/broodmother/initialize_ai_brain()
	. = ..()
	if(. && ai_brain)
		ai_brain.vision_range = 8
		ai_brain.intelligence = AI_SMART
		ai_brain.wander = TRUE

/mob/living/simple_mob/animal/giant_spider/broodmother/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/broodmother_spawn_brood,
		/datum/ai_behavior/broodmother_launch_brood,
		/datum/ai_behavior/ranged_attack,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/animal/giant_spider/broodmother/get_ai_target_selectors()
	var/static/list/L = list(/datum/target_selector/prefer_players, /datum/target_selector/closest)
	return L

// ---------------------------------------------------------------------------
// 1. Spawn brood (legacy I_DISARM) — birth a swarm at the broodmother's feet
//    when enemies are clustered nearby (2+ within 4 tiles) or the current
//    target is within 4 tiles.
// ---------------------------------------------------------------------------

/datum/ai_behavior/broodmother_spawn_brood
	name = "spawn brood"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 6 SECONDS
	min_range = 0
	max_range = 10

/datum/ai_behavior/broodmother_spawn_brood/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/giant_spider/broodmother)

/datum/ai_behavior/broodmother_spawn_brood/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/giant_spider/broodmother/BM = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(BM) || !threat)
		return null
	// should_special_attack(): don't birth past the brood cap.
	if(!BM.can_spawn_brood())
		return null
	if(!BM.can_special_attack(threat))
		return null
	// Count nearby attackable enemies (legacy tallied list_targets within 4).
	var/nearby = 0
	if(brain.model)
		for(var/mob/living/M as anything in brain.model.visible_hostiles)
			if(get_dist(BM, M) <= BROODMOTHER_SWARM_RANGE)
				nearby++
	var/target_close = get_dist(BM, threat) <= BROODMOTHER_SWARM_RANGE
	if(nearby < 2 && !target_close)
		return null
	// More enemies clustered → more valuable to swarm.
	return DQAI_RESULT(75 + min(nearby * 3, 15), threat)

/datum/ai_behavior/broodmother_spawn_brood/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/giant_spider/broodmother/BM = brain.holder
	if(!istype(BM) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	BM.last_special_attack = world.time
	BM.spawn_brood(target)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 2. Launch brood (legacy I_HURT) — fling broodlings at a target more than 4
//    tiles away.
// ---------------------------------------------------------------------------

/datum/ai_behavior/broodmother_launch_brood
	name = "launch brood"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 6 SECONDS
	min_range = 5
	max_range = 10

/datum/ai_behavior/broodmother_launch_brood/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/giant_spider/broodmother)

/datum/ai_behavior/broodmother_launch_brood/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/giant_spider/broodmother/BM = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(BM) || !threat)
		return null
	if(!BM.can_spawn_brood())
		return null
	if(!BM.can_special_attack(threat))
		return null
	// Legacy: only fling at distant targets (> 4 tiles).
	if(get_dist(BM, threat) <= BROODMOTHER_SWARM_RANGE)
		return null
	return DQAI_RESULT(74, threat)

/datum/ai_behavior/broodmother_launch_brood/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/giant_spider/broodmother/BM = brain.holder
	if(!istype(BM) || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	BM.last_special_attack = world.time
	BM.launch_brood(target)
	return DQ_BEHAVIOR_DONE

#undef BROODMOTHER_SWARM_RANGE
