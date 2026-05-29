// Utility / non-combat behaviors. Pick up items, disarm, scavenge.

// --- Scavenge weapon --------------------------------------------------------
// Unarmed mobs with hands will pick up dropped weapons that grant behaviors.
// The new behaviors automatically appear in effective_behaviors on next slow tick.

/datum/ai_behavior/scavenge_weapon
	name = "scavenge weapon"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_ITEM
	no_threat_required = TRUE  // pick up even if no current threat — be ready

/datum/ai_behavior/scavenge_weapon/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.has_hands

/datum/ai_behavior/scavenge_weapon/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	// Already holding something? Skip unless we could swap to something better.
	var/obj/item/current = owner.get_active_held_item()
	var/current_grants = current ? LAZYLEN(current.get_dq_granted_behaviors()) : 0

	var/obj/item/best
	var/best_grants = current_grants
	for(var/obj/item/I in view(5, owner))
		var/grants = LAZYLEN(I.get_dq_granted_behaviors())
		if(grants > best_grants)
			best_grants = grants
			best = I
	if(!best)
		return null
	// Score scales with how much the item gives us, biased slightly down vs combat.
	return DQAI_RESULT(20 + best_grants * 10, best)

/datum/ai_behavior/scavenge_weapon/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || QDELETED(target))
		return DQ_BEHAVIOR_FAILED
	var/obj/item/I = target
	if(!owner.Adjacent(I))
		step_to(owner, I)
		return DQ_BEHAVIOR_CONTINUE
	// Adjacent — pick up.
	owner.put_in_any_hand_if_possible(I)
	if(I.loc == owner)
		owner.visible_message(span_notice("[owner] picks up [I]."))
		// Force rebuild on next strategic tick — happens naturally via slow tick.
		brain.invalidate_selection()
		return DQ_BEHAVIOR_DONE
	return DQ_BEHAVIOR_FAILED
