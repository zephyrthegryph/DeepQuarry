// Ysbryd port — restores the "only-visible-to-one-victim" haunting behavior
// from the deleted /datum/ai_holder/simple_mob/ysbryd.
//
// Legacy flavor, faithfully reconstructed:
//   * The ysbryd binds itself to a single chosen victim. While bound, only that
//     victim can see it (VIS_EVENT_INVIS), and the mob steadily piles on fear,
//     hallucinations, ominous rhyming threats and ghostly sounds. That victim
//     bookkeeping (connect_target / disconnect_target / handle_target) already
//     lives on the mob and runs from Life(); this port just keeps the binding
//     pointed at whoever the brain has decided to hunt — the job the legacy
//     handle_stance_strategical() did each strategic tick.
//   * Losing the target disconnects the binding (legacy lose_target override).
//   * The legacy find_target only re-acquired once a minute. Approximated with
//     a per-mob re-acquire latch so it doesn't ping-pong victims.
//   * It's slow but relentless: melee + maul fall out of the generic behaviors,
//     and the mob's own Life() speed-boost-when-hurt survives untouched.

/mob/living/simple_mob/ysbryd
	use_modern_ai = TRUE
	/// world.time before which the brain shouldn't switch victims (legacy
	/// find_target_cooldown = 1 MINUTE gate).
	var/ysbryd_reacquire_after = 0

/mob/living/simple_mob/ysbryd/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/ysbryd_haunt_bind,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/idle_wander,
	)
	return L

// ---------------------------------------------------------------------------
// Haunt binding — keep the one-victim visibility link synced to the brain's
// current target. Background priority: it's bookkeeping, never a combat choice.
// ---------------------------------------------------------------------------

/datum/ai_behavior/ysbryd_haunt_bind
	name = "haunt binding"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE

/datum/ai_behavior/ysbryd_haunt_bind/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/ysbryd)

/datum/ai_behavior/ysbryd_haunt_bind/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/ysbryd/Y = brain.holder
	if(!istype(Y) || Y.stat == DEAD || Y.client)
		return null
	// Always eligible at low score so it runs whenever nothing else does and
	// keeps the binding fresh.
	return DQAI_RESULT(2, Y)

/datum/ai_behavior/ysbryd_haunt_bind/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/ysbryd/Y = brain.holder
	if(!istype(Y))
		return DQ_BEHAVIOR_DONE
	var/mob/living/threat = brain.primary_threat

	if(threat)
		// Honor the legacy 1-minute re-acquire gate: don't abandon a live victim
		// for a new one until the cooldown lapses. Once bound, stay bound.
		if(Y.chosen_target && Y.chosen_target != threat && world.time < Y.ysbryd_reacquire_after && Y.chosen_target.stat < DEAD)
			return DQ_BEHAVIOR_DONE
		if(threat != Y.chosen_target)
			if(Y.chosen_target)
				Y.disconnect_target()
			Y.connect_target(threat)
			Y.ysbryd_reacquire_after = world.time + 1 MINUTE
	else if(Y.chosen_target)
		// Brain dropped the target — release the haunt.
		Y.disconnect_target()
	return DQ_BEHAVIOR_DONE
