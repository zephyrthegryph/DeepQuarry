// Modern-AI port for /mob/living/simple_mob/animal/sif/kururak — Sivian
// pack-hunting felinids whose aggression is driven by a pack "instinct" /
// "ace" hierarchy.
//
// Legacy AI: /datum/ai_holder/simple_mob/intentional/kururak
//   hostile = FALSE, retaliate = TRUE, cooperative = TRUE, can_flee = TRUE,
//   flee_when_dying = TRUE.
//
//   handle_special_strategical(): recomputed the pack hierarchy every strategic
//     tick — the kururak with the highest `instinct` gets the /datum/modifier/ace
//     buff (via pack_gauge()/detect_instinct()), everyone else follows the ace,
//     and ONLY an ace becomes hostile (hunts on sight). Non-aces stay passive
//     and only retaliate.
//   pre_special_attack(): chose a_intent — GRAB if adjacent (rending strike),
//     DISARM if the target is a flashable carbon/silicon (tail flash), else HURT.
//   do_special_attack(): I_DISARM -> tail_flash, I_GRAB -> rending_strike. Gated
//     by should_special_attack() == has the ace buff.
//   post_melee_attack(): an ace calls for pack help after landing a melee hit.
//
// The helper procs (tail_flash, rending_strike, detect_instinct, pack_gauge,
// do_special_attack, should_special_attack) all still live on the kururak mob
// and are reused verbatim.

/mob/living/simple_mob/animal/sif/kururak
	use_modern_ai = TRUE

/mob/living/simple_mob/animal/sif/kururak/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/kururak_pack_instinct,
		/datum/ai_behavior/kururak_special,
		/datum/ai_behavior/kururak_pack_rally,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/follow_leader,
		/datum/ai_behavior/flee_low_hp,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// ---------------------------------------------------------------------------
// Pack instinct — the strategic hierarchy tick. Background-priority (runs even
// with no threat) and slow-cooldowned so it just keeps the ace/follow state
// fresh. Mirrors legacy handle_special_strategical().
// ---------------------------------------------------------------------------

/datum/ai_behavior/kururak_pack_instinct
	name = "assess pack instinct"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE
	cooldown = 4 SECONDS

/datum/ai_behavior/kururak_pack_instinct/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/kururak)

/datum/ai_behavior/kururak_pack_instinct/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/kururak/K = brain.holder
	if(!istype(K))
		return null
	// Always worth a tiny score so it cycles in when nothing else is running.
	return DQAI_RESULT(1, K)

/datum/ai_behavior/kururak_pack_instinct/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/kururak/K = brain.holder
	if(!istype(K))
		return DQ_BEHAVIOR_FAILED
	// Recompute the ace buff (highest instinct in range gets it).
	var/mob/living/simple_mob/animal/sif/kururak/highest = K.detect_instinct()
	if(highest == K)
		K.add_modifier(/datum/modifier/ace, 60 SECONDS)
	else
		K.remove_modifiers_of_type(/datum/modifier/ace)

	var/has_ace = K.has_modifier_of_type(/datum/modifier/ace)
	if(K.obey_pack_rule)
		if(has_ace)
			// The pack leader never follows another kururak.
			brain.set_leader(null)
		else if(highest && highest != K)
			brain.set_leader(highest)

	// Only an ace hunts on sight; everyone else stays passive (retaliate-only).
	K.ai_attack_on_sight = has_ace
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Special attack — tail flash (disarm) or rending strike (grab). Picks the
// intent the way legacy pre_special_attack() did, then routes through the
// mob's own special_attack_target -> do_special_attack pipeline.
// ---------------------------------------------------------------------------

/datum/ai_behavior/kururak_special
	name = "kururak special strike"
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB

/datum/ai_behavior/kururak_special/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/kururak)

/datum/ai_behavior/kururak_special/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/kururak/K = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(K) || !threat)
		return null
	// can_special_attack covers range + special_attack_cooldown;
	// should_special_attack requires the ace buff (only the leader specials).
	if(!K.can_special_attack(threat) || !K.should_special_attack(threat))
		return null
	return DQAI_RESULT(70, threat)

/datum/ai_behavior/kururak_special/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/kururak/K = brain.holder
	if(!istype(K) || !isliving(target))
		return DQ_BEHAVIOR_FAILED
	var/mob/living/L = target
	// Intent selection, faithful to legacy pre_special_attack():
	//   GRAB (rending strike) if adjacent — armor-ignoring agonizing wound.
	//   DISARM (tail flash) if the victim has unprotected eyes / is a borg.
	//   else HURT.
	K.a_intent = I_HURT
	if(K.Adjacent(L))
		K.a_intent = I_GRAB
	if(iscarbon(L))
		var/mob/living/carbon/C = L
		if(!C.eyecheck() && K.a_intent != I_GRAB)
			K.a_intent = I_DISARM
	if(issilicon(L) && K.a_intent != I_GRAB)
		K.a_intent = I_DISARM
	K.special_attack_target(L)
	K.a_intent = I_HURT  // legacy post_special_attack reset
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Pack rally — an ace calls for help after melee, like legacy
// post_melee_attack() -> request_help(). Triggered by landing a hit on a
// threat; cheap re-use of the generic call_for_help mechanics but gated on the
// ace buff so only the leader rallies.
// ---------------------------------------------------------------------------

/datum/ai_behavior/kururak_pack_rally
	name = "rally the pack"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	cooldown = 15 SECONDS

/datum/ai_behavior/kururak_pack_rally/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/kururak)

/datum/ai_behavior/kururak_pack_rally/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/kururak/K = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(K) || !threat)
		return null
	if(!K.has_modifier_of_type(/datum/modifier/ace))
		return null
	if(!brain.model || !length(brain.model.visible_friendlies))
		return null
	// Only worth rallying once we're actually in a fight (recently swung).
	if(world.time > brain.last_attack_at + 5 SECONDS)
		return null
	return DQAI_RESULT(48, threat)

/datum/ai_behavior/kururak_pack_rally/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/kururak/K = brain.holder
	if(!istype(K) || !isliving(target))
		return DQ_BEHAVIOR_FAILED
	K.visible_message(span_warning("[K] yowls, calling the pack!"))
	for(var/mob/living/ally as anything in brain.model.visible_friendlies)
		if(!ally.ai_brain)
			continue
		ally.ai_brain.add_personal(target, DQ_DISPOSITION_HOSTILE, 60 SECONDS, "pack rally")
		SEND_SIGNAL(ally, COMSIG_DQAI_ALLY_DISTRESS, K, target)
	return DQ_BEHAVIOR_DONE
