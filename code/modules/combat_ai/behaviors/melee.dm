// Melee combat behaviors.

// --- Basic melee attack -----------------------------------------------------
// Standard adjacent strike using the simple_mob's melee_damage_lower/upper
// values via the existing attack_target proc. Delegates to the existing
// combat code so animations, hit sounds, modifiers all keep working.

/datum/ai_behavior/melee_attack
	name = "melee attack"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1

/datum/ai_behavior/melee_attack/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.melee_damage_upper > 0

/datum/ai_behavior/melee_attack/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_target()
	if(!owner || !threat)
		return null
	if(!owner.Adjacent(threat))
		return null
	if(!owner.checkClickCooldown())
		return null
	// Mid-band score; charge_slam/web_spit beat plain melee when in their range.
	return DQAI_RESULT(40, threat)

/datum/ai_behavior/melee_attack/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return DQ_BEHAVIOR_FAILED
	// The swing is the mob's own "mob_attacks.melee" op: the same requirements and refusals as any other actor's.
	if(!brain.perform_attack_op(SM, target, "mob_attacks.melee"))
		return DQ_BEHAVIOR_FAILED
	EXPIRY_STAMP(brain, last_attack_at, CLOCK_WORLD)
	return DQ_BEHAVIOR_DONE  // single-tick action; attack_target handles cooldown

// --- Charge slam ------------------------------------------------------------
// Telegraphed mid-range gap-closer. Mob freezes, plays a windup, then dashes
// to the target tile, dealing bonus damage on impact. Player-readable.

/datum/ai_behavior/charge_slam
	name = "charge slam"
	desc = "A telegraphed dash that deals heavy damage on impact."
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	min_range = 3
	max_range = 6
	cooldown = 12 SECONDS

/datum/ai_behavior/charge_slam/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.melee_damage_upper > 0

/datum/ai_behavior/charge_slam/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_target()
	if(!owner || !threat)
		return null
	var/dist = get_dist(owner, threat)
	if(dist < min_range || dist > max_range)
		return null
	// Score high — this is the showpiece. Decays slightly with distance.
	return DQAI_RESULT(80 - dist * 2, threat)

/datum/ai_behavior/charge_slam/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/owner = brain.get_owner()
	act_message(owner, target, others = span_danger("%U% crouches, focused on %T%!"), \
		blind = span_warning("You hear something heavy shift its weight."))
	// The wind-up and the dash are one op of the mob ("mob_attacks.charge", a wait() then the dash): the brain is busy until it ends and
	// the tactic ends with its outcome (op_wait_ended()); a tactic that is replaced or stopped cancels it.
	if(!brain.begin_waiting_op("mob_attacks.charge", target))
		return DQ_BEHAVIOR_FAILED
	return DQ_BEHAVIOR_CONTINUE

TYPE_TABLE(/datum/ai_behavior/charge_slam, get_player_verb_info, list( \
		"name" = "Charge Slam", \
		"desc" = "Crouch, then dash at a target for heavy damage.", \
		"category" = "Combat", \
		"auto_target" = FALSE, \
	))
