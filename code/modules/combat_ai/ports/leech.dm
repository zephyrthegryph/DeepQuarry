// Modern-AI port for /mob/living/simple_mob/animal/sif/leech.
//
// The legacy /datum/ai_holder/simple_mob/intentional/leech was a low-vision
// (range 3) ambush worm that:
//   * pre_special_attack(A) picked an intent by reading the target's state —
//       I_GRAB  → infest a downed/incapacitated, non-synthetic human (do_infest)
//       I_DISARM→ poison-stun a standing human                       (poison_inject)
//       I_HURT  → just bite anything else (handled by normal melee)
//     do_special_attack() ran the matching helper.
//   * handle_special_strategical() retargeted its home_turf to nearby water
//     when it had no host and wasn't already standing in water.
//   * special_flee_check() made it flee (back toward water) whenever it had no
//     host and was out of water — leeches don't want to dry out.
//   * mauling / returns_home / can_flee / max_home_distance = 1 (stay near water).
//
// Modern port: infest and poison become OVERRIDE behaviors with the target-state
// gating from pre_special_attack folded into evaluate(). A strategical "seek
// water" behavior (IDLE class, no_threat_required) reproduces the home-retarget
// + the special_flee_check pull back to water as one INTERRUPT-class retreat.
// do_special_attack / poison_inject / do_infest / handle_special all stay on the
// mob untouched; the behaviors call poison_inject / do_infest directly.

/mob/living/simple_mob/animal/sif/leech
	use_modern_ai = TRUE

/mob/living/simple_mob/animal/sif/leech/initialize_ai_brain()
	. = ..()
	if(. && ai_brain)
		ai_brain.vision_range = 3
		ai_brain.mauling = TRUE
		ai_brain.returns_home = TRUE
		ai_brain.max_home_distance = 1   // never stray far from water unless infesting

/mob/living/simple_mob/animal/sif/leech/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/leech_seek_water,
		/datum/ai_behavior/leech_infest,
		/datum/ai_behavior/leech_poison,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/return_home,
		/datum/ai_behavior/idle_wander,
	)
	return L

// ---------------------------------------------------------------------------
// Shared helper — does the leech currently want to be in water? (No host, and
// not already standing in water.) Drives both the home-retarget and the flee.
// ---------------------------------------------------------------------------

/proc/dq_leech_wants_water(mob/living/simple_mob/animal/sif/leech/SL)
	if(!istype(SL) || SL.host)
		return FALSE
	return !istype(get_turf(SL), /turf/simulated/floor/water)

// ---------------------------------------------------------------------------
// 1. Seek water — combines the legacy handle_special_strategical() home-retarget
//    with special_flee_check(): when hostless and out of water, abandon the
//    current fight and scuttle to the nearest water tile. INTERRUPT so it
//    overrides combat (the leech values not drying out over a kill).
// ---------------------------------------------------------------------------

/datum/ai_behavior/leech_seek_water
	name = "seek water"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_TURF
	no_threat_required = TRUE

/datum/ai_behavior/leech_seek_water/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/leech)

/datum/ai_behavior/leech_seek_water/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/leech/SL = brain.holder
	if(!dq_leech_wants_water(SL))
		return null
	// Find the nearest water tile in view; also retarget home to it so the
	// generic return_home behavior keeps anchoring us there afterward.
	var/turf/best = null
	var/best_dist = INFINITY
	for(var/turf/simulated/floor/water/W in view(SL, 10))
		var/d = get_dist(SL, W)
		if(d < best_dist)
			best_dist = d
			best = W
	if(!best)
		return null
	brain.home_turf = best
	return DQAI_RESULT(110, best)

/datum/ai_behavior/leech_seek_water/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/leech/SL = brain.holder
	if(!istype(SL) || !target)
		return DQ_BEHAVIOR_FAILED
	// Done once we actually reach water (or otherwise gain a host).
	if(!dq_leech_wants_water(SL))
		return DQ_BEHAVIOR_DONE
	if(get_turf(SL) == target)
		return DQ_BEHAVIOR_DONE
	if(!brain.smart_step_toward(target, 0))
		step_to(SL, target)
	return DQ_BEHAVIOR_CONTINUE

// ---------------------------------------------------------------------------
// 2. Infest (legacy I_GRAB) — burrow into a downed/incapacitated organic human.
// ---------------------------------------------------------------------------

/datum/ai_behavior/leech_infest
	name = "leech infest"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 4 SECONDS
	min_range = 0
	max_range = 1

/datum/ai_behavior/leech_infest/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/leech)

/datum/ai_behavior/leech_infest/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/leech/SL = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(SL) || SL.host)   // already have a host; don't grab another
		return null
	if(!ishuman(threat))
		return null
	var/mob/living/carbon/human/H = threat
	if(H.isSynthetic())
		return null
	if(!SL.can_special_attack(H))
		return null
	// Legacy infest condition: target is incapacitated / stat'd / resting / para'd.
	if(!(H.incapacitated() || (H.stat && H.stat != DEAD) || H.resting || H.paralysis))
		return null
	// Highest-value special — getting a host is the leech's whole goal.
	return DQAI_RESULT(95, H)

/datum/ai_behavior/leech_infest/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/leech/SL = brain.holder
	if(!istype(SL) || !iscarbon(target))
		return DQ_BEHAVIOR_FAILED
	var/mob/living/carbon/C = target
	SL.last_special_attack = world.time
	SL.do_infest(SL, C)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// 3. Poison (legacy I_DISARM) — venom-stun a standing organic human so it can
//    be infested next.
// ---------------------------------------------------------------------------

/datum/ai_behavior/leech_poison
	name = "leech venom"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 4 SECONDS
	min_range = 0
	max_range = 1

/datum/ai_behavior/leech_poison/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/leech)

/datum/ai_behavior/leech_poison/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/leech/SL = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(SL) || SL.host)
		return null
	if(!ishuman(threat))
		return null
	var/mob/living/carbon/human/H = threat
	if(H.isSynthetic())
		return null
	if(!SL.can_special_attack(H))
		return null
	// Legacy poison condition: target still on its feet (not yet infest-ready).
	if(H.incapacitated() || (H.stat && H.stat != DEAD) || H.resting || H.paralysis)
		return null
	return DQAI_RESULT(80, H)

/datum/ai_behavior/leech_poison/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/leech/SL = brain.holder
	if(!istype(SL) || !iscarbon(target))
		return DQ_BEHAVIOR_FAILED
	var/mob/living/carbon/C = target
	SL.last_special_attack = world.time
	SL.poison_inject(SL, C)
	return DQ_BEHAVIOR_DONE
