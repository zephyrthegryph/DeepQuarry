// Social / signalling behaviors. No damage; communicate intent or pull aggro.

// --- Threaten ---------------------------------------------------------------
// Pre-combat verbal warning. Lets players react before the mob commits to
// engaging. Fires once at the start of combat.

/datum/ai_behavior/threaten
	name = "threaten"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED)
	cooldown = 20 SECONDS

	var/static/list/threats = list(
		"snarls at",
		"bares its teeth at",
		"hisses at",
		"locks eyes with",
		"growls low at",
	)

/datum/ai_behavior/threaten/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat)
		return null
	// Only when fresh — high score for one tick after target change, then nothing.
	var/dist = get_dist(owner, threat)
	if(dist > brain.vision_range)
		return null
	return DQAI_RESULT(45, threat)

/datum/ai_behavior/threaten/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/owner = brain.get_owner()
	owner.visible_message(span_warning("[owner] [pick(threats)] [target]!"))
	return DQ_BEHAVIOR_DONE

// --- Call for help ----------------------------------------------------------
// Broadcasts an ally-distress signal so faction-mates in range converge.

/datum/ai_behavior/call_for_help
	name = "call for help"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_DAMAGE_TAKEN)
	cooldown = 30 SECONDS

/datum/ai_behavior/call_for_help/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	// Only worth calling if there are allies nearby.
	if(!brain.model || !length(brain.model.visible_friendlies))
		return null
	return DQAI_RESULT(50, threat)

/datum/ai_behavior/call_for_help/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/owner = brain.get_owner()
	owner.visible_message(span_warning("[owner] sounds an alarm!"))
	// Forward the attacker to each friendly's brain so they upgrade them to HOSTILE.
	for(var/mob/living/ally as anything in brain.model.visible_friendlies)
		if(!ally.ai_brain)
			continue
		ally.ai_brain.add_personal(target, DQ_DISPOSITION_HOSTILE, 60 SECONDS, "ally distress")
		SEND_SIGNAL(ally, COMSIG_DQAI_ALLY_DISTRESS, owner, target)
	return DQ_BEHAVIOR_DONE
