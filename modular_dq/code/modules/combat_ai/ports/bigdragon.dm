// Bigdragon port — restores the three-special-attack rotation (fire breath,
// charge, tail sweep / repulse) that lived on
// /datum/ai_holder/simple_mob/intentional/dragon.
//
// Each attack becomes a discrete behavior. Brain selection chooses based on
// situation: surrounded → tail sweep, far + line of sight → charge,
// otherwise → fire breath. The mob's existing chargestart / firebreathstart /
// repulse procs are reused.

/mob/living/simple_mob/vore/bigdragon
	use_modern_ai = TRUE

/mob/living/simple_mob/vore/bigdragon/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/dragon_tail_sweep,
		/datum/ai_behavior/dragon_charge,
		/datum/ai_behavior/dragon_fire_breath,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

/mob/living/simple_mob/vore/bigdragon/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/prefer_players,
		/datum/target_selector/closest,
	)
	return L

// ---------------------------------------------------------------------------
// Tail sweep — when 2+ hostiles are within 2 tiles, throw them all back.
// ---------------------------------------------------------------------------

/datum/ai_behavior/dragon_tail_sweep
	name = "dragon tail sweep"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 8 SECONDS
	min_range = 0
	max_range = 2

/datum/ai_behavior/dragon_tail_sweep/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/bigdragon)

/datum/ai_behavior/dragon_tail_sweep/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.holder
	if(!D || D.nospecial || !D.specialtoggle)
		return null
	if(!brain.primary_threat || !brain.model)
		return null
	var/yeet_threshold = 2
	var/tally = 0
	for(var/mob/living/M as anything in brain.model.visible_hostiles)
		if(get_dist(D, M) <= 2)
			tally++
	if(tally < yeet_threshold)
		return null
	return DQAI_RESULT(80, brain.primary_threat)

/datum/ai_behavior/dragon_tail_sweep/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.holder
	if(!D || D.nospecial || !D.specialtoggle)
		return DQ_BEHAVIOR_FAILED
	D.repulse()
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/dragon_tail_sweep/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Tail Sweep",
		"desc" = "Knock all adjacent mobs away with a tail strike.",
		"category" = "Dragon",
		"auto_target" = TRUE,
	)
	return L

// ---------------------------------------------------------------------------
// Charge — when threat is >5 tiles away with line of sight.
// ---------------------------------------------------------------------------

/datum/ai_behavior/dragon_charge
	name = "dragon charge"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 8 SECONDS
	min_range = 6
	max_range = 10

/datum/ai_behavior/dragon_charge/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/bigdragon)

/datum/ai_behavior/dragon_charge/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.holder
	if(!D || D.nospecial || !D.specialtoggle)
		return null
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	var/dist = get_dist(D, threat)
	if(dist <= 5 || dist > 10)
		return null
	// Need line of sight. Use check_trajectory's default pass_flags
	// (PASSTABLE|PASSGLASS|PASSGRILLE) so the dragon can charge through
	// windows and grilles like the legacy behavior allowed.
	if(!(threat in check_trajectory(threat, D)))
		return null
	return DQAI_RESULT(70, threat)

/datum/ai_behavior/dragon_charge/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.holder
	if(!D || D.nospecial || !D.specialtoggle)
		return DQ_BEHAVIOR_FAILED
	D.chargestart(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/dragon_charge/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Charge",
		"desc" = "Lunge at a distant target with crushing force.",
		"category" = "Dragon",
		"auto_target" = FALSE,
	)
	return L

// ---------------------------------------------------------------------------
// Fire breath — default ranged attack.
// ---------------------------------------------------------------------------

/datum/ai_behavior/dragon_fire_breath
	name = "dragon fire breath"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	cooldown = 6 SECONDS
	min_range = 1
	max_range = 8

/datum/ai_behavior/dragon_fire_breath/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/bigdragon)

/datum/ai_behavior/dragon_fire_breath/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.holder
	if(!D || D.norange || !D.flametoggle)
		return null
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	var/dist = get_dist(D, threat)
	if(dist < 1 || dist > 8)
		return null
	return DQAI_RESULT(60, threat)

/datum/ai_behavior/dragon_fire_breath/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.holder
	if(!D || D.norange || !D.flametoggle)
		return DQ_BEHAVIOR_FAILED
	D.firebreathstart(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/dragon_fire_breath/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Fire Breath",
		"desc" = "Breathe a cone of flame at a target.",
		"category" = "Dragon",
		"auto_target" = FALSE,
	)
	return L
