// Modern-AI port for /mob/living/simple_mob/glitch_boss.
//
// The legacy version stored a "next special attack" integer and used the AI
// holder's pre_special_attack hook to pick one, then ran a giant switch in
// do_special_attack(). In the modern framework each special is its own
// behavior, each with its own evaluate() gating. The brain naturally cycles
// because each one cools down for ~15s after firing, and pre_special_attack's
// "don't repeat last attack" rule falls out of independent cooldowns.
//
// The seven helper procs (make_ads, bombardment, bomb_lines, bullethell,
// create_illusions, confuse_inflict, speed_up_boost) stay on the mob — the
// behaviors are stateless adapters that call them.

/mob/living/simple_mob/glitch_boss
	use_modern_ai = TRUE

/mob/living/simple_mob/glitch_boss/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/glitch_ads,
		/datum/ai_behavior/glitch_calldown,
		/datum/ai_behavior/glitch_bomb_lines,
		/datum/ai_behavior/glitch_bullethell,
		/datum/ai_behavior/glitch_illusions,
		/datum/ai_behavior/glitch_confusion,
		/datum/ai_behavior/glitch_speedup,
		/datum/ai_behavior/ranged_attack,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/glitch_boss/get_ai_target_selectors()
	var/static/list/L = list(/datum/target_selector/prefer_players, /datum/target_selector/closest)
	return L

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Count live, non-illusion hostiles the boss can target.
/proc/dq_glitch_real_target_count(datum/ai_brain/brain)
	. = 0
	if(!brain.model)
		return 0
	for(var/mob/living/M as anything in brain.model.visible_hostiles)
		if(istype(M, /mob/living/simple_mob/glitch_boss_fake))
			continue
		. += 1

/// Count current /mob/living/simple_mob/glitch_boss_fake illusions in view.
/proc/dq_glitch_illusion_count(datum/ai_brain/brain)
	. = 0
	for(var/mob/living/simple_mob/glitch_boss_fake/F in view(brain.vision_range, brain.holder))
		. += 1

// ---------------------------------------------------------------------------
// 1. Popup ads on player victims
// ---------------------------------------------------------------------------

/datum/ai_behavior/glitch_ads
	name = "spam popup ads"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS
	min_range = 0
	max_range = 10

/datum/ai_behavior/glitch_ads/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/glitch_boss)

/datum/ai_behavior/glitch_ads/evaluate(datum/ai_brain/brain, atom/source)
	if(!brain.primary_threat) return null
	// Worthless if no clients to spam.
	var/has_client = FALSE
	for(var/mob/living/M as anything in brain.model?.visible_hostiles)
		if(M.client)
			has_client = TRUE
			break
	if(!has_client)
		return null
	return DQAI_RESULT(70, brain.primary_threat)

/datum/ai_behavior/glitch_ads/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/glitch_boss/GB = brain.holder
	GB.make_ads(target)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 2. Call-down bombardment (clustered enemies)
// ---------------------------------------------------------------------------

/datum/ai_behavior/glitch_calldown
	name = "call-down bombardment"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS

/datum/ai_behavior/glitch_calldown/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/glitch_boss)

/datum/ai_behavior/glitch_calldown/evaluate(datum/ai_brain/brain, atom/source)
	if(!brain.primary_threat) return null
	if(dq_glitch_real_target_count(brain) < 1)
		return null
	return DQAI_RESULT(72, brain.primary_threat)

/datum/ai_behavior/glitch_calldown/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/glitch_boss/GB = brain.holder
	GB.bombardment(target)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 3. Bomb lines on a target
// ---------------------------------------------------------------------------

/datum/ai_behavior/glitch_bomb_lines
	name = "bomb lines"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS

/datum/ai_behavior/glitch_bomb_lines/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/glitch_boss)

/datum/ai_behavior/glitch_bomb_lines/evaluate(datum/ai_brain/brain, atom/source)
	if(!brain.primary_threat) return null
	if(dq_glitch_real_target_count(brain) < 1)
		return null
	return DQAI_RESULT(72, brain.primary_threat)

/datum/ai_behavior/glitch_bomb_lines/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/glitch_boss/GB = brain.holder
	GB.bomb_lines(target)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 4. Bullet hell (always available, fallback)
// ---------------------------------------------------------------------------

/datum/ai_behavior/glitch_bullethell
	name = "bullet hell"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 12 SECONDS

/datum/ai_behavior/glitch_bullethell/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/glitch_boss)

/datum/ai_behavior/glitch_bullethell/evaluate(datum/ai_brain/brain, atom/source)
	if(!brain.primary_threat) return null
	// Always rated mid-tier so it fires when nothing else is available.
	return DQAI_RESULT(60, brain.primary_threat)

/datum/ai_behavior/glitch_bullethell/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/glitch_boss/GB = brain.holder
	GB.bullethell(target)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 5. Spawn illusions
// ---------------------------------------------------------------------------

/datum/ai_behavior/glitch_illusions
	name = "spawn illusions"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS

/datum/ai_behavior/glitch_illusions/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/glitch_boss)

/datum/ai_behavior/glitch_illusions/evaluate(datum/ai_brain/brain, atom/source)
	if(!brain.primary_threat) return null
	if(dq_glitch_illusion_count(brain) > 4)
		return null
	return DQAI_RESULT(72, brain.primary_threat)

/datum/ai_behavior/glitch_illusions/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/glitch_boss/GB = brain.holder
	GB.create_illusions(target)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 6. Confusion (only when 2+ live targets)
// ---------------------------------------------------------------------------

/datum/ai_behavior/glitch_confusion
	name = "inflict confusion"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS

/datum/ai_behavior/glitch_confusion/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/glitch_boss)

/datum/ai_behavior/glitch_confusion/evaluate(datum/ai_brain/brain, atom/source)
	if(!brain.primary_threat) return null
	if(dq_glitch_real_target_count(brain) < 2)
		return null
	return DQAI_RESULT(72, brain.primary_threat)

/datum/ai_behavior/glitch_confusion/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/glitch_boss/GB = brain.holder
	GB.confuse_inflict(target)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 7. Speed-up (best vs single target)
// ---------------------------------------------------------------------------

/datum/ai_behavior/glitch_speedup
	name = "speed-up"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 20 SECONDS

/datum/ai_behavior/glitch_speedup/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/glitch_boss)

/datum/ai_behavior/glitch_speedup/evaluate(datum/ai_brain/brain, atom/source)
	if(!brain.primary_threat) return null
	// Higher score when there's only one real target — matches legacy logic.
	var/single_target = dq_glitch_real_target_count(brain) < 2
	return DQAI_RESULT(single_target ? 85 : 65, brain.primary_threat)

/datum/ai_behavior/glitch_speedup/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/glitch_boss/GB = brain.holder
	GB.speed_up_boost(target)
	return DQ_BEHAVIOR_DONE
