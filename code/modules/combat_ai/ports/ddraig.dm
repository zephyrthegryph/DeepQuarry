// Ddraig port — restores the dragon's special-attack rotation plus the
// "cloak and run when badly hurt" panic from the deleted
// /datum/ai_holder/simple_mob/vore/ddraig.
//
// Legacy flavor, faithfully reconstructed:
//   * Three telegraphed specials, picked at random in the old do_special_attack
//     (rand(1,3) -> lunge / firebreath / tfbeam). Each becomes its own behavior;
//     the brain naturally rotates because they share one special cooldown band
//     and the helpers set ai_brain.busy during their windups. Range gating
//     matches special_attack_min_range..max_range (2..6).
//   * One-time emergency cloak: below 25% HP the dragon turns invisible, bolts,
//     and stays cloaked for a minute (used_invis latch). Reproduced as an
//     INTERRUPT behavior with a once-per-life latch on the mob.
//   * While cloaked it flees rather than fights (legacy engage_target's
//     dq_get_cloaked -> STANCE_FLEE).
//   * Vore + melee fall out of the generic melee_attack path (apply_attack
//     pounces/eats). The mob's lunge/firebreath/tfbeam helpers are reused as-is.

/mob/living/simple_mob/vore/ddraig
	/// Once-per-life emergency-invisibility latch (legacy ai_holder.used_invis).
	var/ddraig_used_invis = FALSE

/mob/living/simple_mob/vore/ddraig/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/ddraig_panic_cloak,
		/datum/ai_behavior/ddraig_flee_cloaked,
		/datum/ai_behavior/ddraig_lunge,
		/datum/ai_behavior/ddraig_firebreath,
		/datum/ai_behavior/ddraig_tfbeam,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/investigate_noise,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

/mob/living/simple_mob/vore/ddraig/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/prefer_players,
		/datum/target_selector/closest,
	)
	return L

// ---------------------------------------------------------------------------
// Special-attack rotation. All three sit in the same range band (2..6) and
// share a cooldown so the dragon cycles through them like the old rand(1,3).
// The helper procs set ai_brain.busy during their telegraphs, so the brain
// won't reselect mid-windup.
// ---------------------------------------------------------------------------

/// Common gate: a ddraig with a live target in special range that isn't
/// player-controlled (legacy do_special_attack bailed for ckey'd mobs).
/proc/dq_ddraig_special_ok(datum/ai_brain/brain)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D) || D.client)
		return null
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	var/dist = get_dist(D, threat)
	if(dist < D.special_attack_min_range || dist > D.special_attack_max_range)
		return null
	return threat

// --- Lunge -----------------------------------------------------------------

/datum/ai_behavior/ddraig_lunge
	name = "ddraig lunge"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS
	min_range = 2
	max_range = 6

/datum/ai_behavior/ddraig_lunge/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/ddraig)

/datum/ai_behavior/ddraig_lunge/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/threat = dq_ddraig_special_ok(brain)
	if(!threat)
		return null
	// Lunge wants an edible, throwable target; otherwise it no-ops. Bias it for
	// closer prey so it reads as a gap-closing pounce.
	return DQAI_RESULT(70, threat)

/datum/ai_behavior/ddraig_lunge/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D))
		return DQ_BEHAVIOR_FAILED
	D.lunge(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/ddraig_lunge/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Lunge",
		"desc" = "Telegraph, then leap at a target to knock them down.",
		"category" = "Dragon",
		"auto_target" = FALSE,
	)
	return L

// --- Fire breath -----------------------------------------------------------

/datum/ai_behavior/ddraig_firebreath
	name = "ddraig fire breath"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS
	min_range = 2
	max_range = 6

/datum/ai_behavior/ddraig_firebreath/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/ddraig)

/datum/ai_behavior/ddraig_firebreath/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/threat = dq_ddraig_special_ok(brain)
	if(!threat)
		return null
	return DQAI_RESULT(68, threat)

/datum/ai_behavior/ddraig_firebreath/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D))
		return DQ_BEHAVIOR_FAILED
	D.firebreathstart(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/ddraig_firebreath/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Fire Breath",
		"desc" = "Open your maw and spew a gout of flame at a target.",
		"category" = "Dragon",
		"auto_target" = FALSE,
	)
	return L

// --- Transformation beam ---------------------------------------------------

/datum/ai_behavior/ddraig_tfbeam
	name = "ddraig polymorph beam"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS
	min_range = 2
	max_range = 6

/datum/ai_behavior/ddraig_tfbeam/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/ddraig)

/datum/ai_behavior/ddraig_tfbeam/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/threat = dq_ddraig_special_ok(brain)
	if(!threat)
		return null
	return DQAI_RESULT(66, threat)

/datum/ai_behavior/ddraig_tfbeam/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D))
		return DQ_BEHAVIOR_FAILED
	D.tfbeam(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/ddraig_tfbeam/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Polymorph Beam",
		"desc" = "Breathe a rainbow beam that briefly transforms a target into a critter.",
		"category" = "Dragon",
		"auto_target" = FALSE,
	)
	return L

// ---------------------------------------------------------------------------
// Emergency cloak — once per life, below 25% HP, vanish and bolt.
// ---------------------------------------------------------------------------

/datum/ai_behavior/ddraig_panic_cloak
	name = "emergency invisibility"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_DAMAGE_TAKEN, COMSIG_DQAI_LOW_HEALTH)
	/// How long the dragon stays cloaked after panicking (legacy spawn(60 SECONDS)).
	var/cloak_duration = 1 MINUTE
	/// How far it flings itself away on activation.
	var/bolt_distance = 8

/datum/ai_behavior/ddraig_panic_cloak/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/ddraig)

/datum/ai_behavior/ddraig_panic_cloak/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D) || D.ddraig_used_invis || !D.maxHealth)
		return null
	if(D.health >= (D.maxHealth * 0.25))
		return null
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	return DQAI_RESULT(150, threat)

/datum/ai_behavior/ddraig_panic_cloak/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D))
		return DQ_BEHAVIOR_FAILED
	D.ddraig_used_invis = TRUE
	D.cloak()
	// Several big steps away, like the legacy stacked step_away calls.
	if(target)
		for(var/i in 1 to 5)
			step_away(D, target, bolt_distance)
	addtimer(CALLBACK(D, TYPE_PROC_REF(/atom/movable, uncloak)), cloak_duration)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Flee while cloaked — don't fight whilst hidden; keep distance until the
// cloak drops. Mirrors the legacy "if dq_get_cloaked -> STANCE_FLEE".
// ---------------------------------------------------------------------------

/datum/ai_behavior/ddraig_flee_cloaked
	name = "flee while cloaked"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB

/datum/ai_behavior/ddraig_flee_cloaked/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/ddraig)

/datum/ai_behavior/ddraig_flee_cloaked/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D) || !dq_get_cloaked(D))
		return null
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	// Below the panic-cloak score so the cloak itself wins on the trigger tick.
	return DQAI_RESULT(140, threat)

/datum/ai_behavior/ddraig_flee_cloaked/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/ddraig/D = brain.holder
	if(!istype(D) || !target)
		return DQ_BEHAVIOR_FAILED
	if(!dq_get_cloaked(D) || get_dist(D, target) >= 10)
		return DQ_BEHAVIOR_DONE
	step_away(D, target, 8)
	return DQ_BEHAVIOR_CONTINUE
