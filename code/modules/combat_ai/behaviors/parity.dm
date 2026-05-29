// Parity behaviors — fill the gaps with the legacy /datum/ai_holder feature set
// so default-behavior mobs feel about the same as before migration.

// --- Maul unconscious target ------------------------------------------------
// Pack predators finish off downed enemies even after the primary threat has
// changed. Lets wolf/spider-style mobs commit kills.

/datum/ai_behavior/maul_unconscious
	name = "maul"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1

/datum/ai_behavior/maul_unconscious/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.melee_damage_upper > 0

/datum/ai_behavior/maul_unconscious/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !brain.model)
		return null
	// Look for unconscious living mobs in melee reach. Prefer faction-enemies but
	// don't strictly require the disposition check — pack predators don't care.
	for(var/mob/living/L in view(1, owner))
		if(L == owner || L.stat == CONSCIOUS || L.stat >= DEAD)
			continue
		if(brain.disposition_to(L) >= DQ_DISPOSITION_FRIENDLY)
			continue
		if(!owner.Adjacent(L))
			continue
		// Slightly above plain melee_attack — finishing kills is high priority.
		return DQAI_RESULT(50, L)
	return null

/datum/ai_behavior/maul_unconscious/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return DQ_BEHAVIOR_FAILED
	SM.attack_target(target)
	return DQ_BEHAVIOR_DONE

// --- Idle speak -------------------------------------------------------------
// Random barks from the mob's say_list while not in combat. Used to be
// `speak_chance` on the ai_holder.

/datum/ai_behavior/idle_speak
	name = "idle speak"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE
	cooldown = 15 SECONDS

/datum/ai_behavior/idle_speak/evaluate(datum/ai_brain/brain, atom/source)
	if(brain.primary_threat)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner || !owner.say_list)
		return null
	if(!length(owner.say_list.speak))
		return null
	return DQAI_RESULT(1, owner)

/datum/ai_behavior/idle_speak/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !owner.say_list)
		return DQ_BEHAVIOR_FAILED
	var/list/speech = owner.say_list.speak
	if(length(speech))
		owner.say(pick(speech))
	return DQ_BEHAVIOR_DONE

// --- Retaliate (wake when hit) ----------------------------------------------
// Some mobs (passive, retaliate) shouldn't ATTACK on sight but SHOULD attack
// back when struck. This behavior gates the standard melee/ranged behaviors
// behind "have I been attacked?" — fires once on damage to promote the
// attacker to primary_threat.

/datum/ai_behavior/retaliate_to_attacker
	name = "retaliate"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_DAMAGE_TAKEN)
	cooldown = 1 SECOND

/datum/ai_behavior/retaliate_to_attacker/evaluate(datum/ai_brain/brain, atom/source)
	var/atom/attacker = brain.model?.get_last_attacker()
	if(!ismob(attacker))
		return null
	// If they're already our primary threat, nothing to do.
	if(attacker == brain.primary_threat)
		return null
	// Promote them.
	return DQAI_RESULT(100, attacker)

/datum/ai_behavior/retaliate_to_attacker/start(datum/ai_brain/brain, atom/target, atom/source)
	// Switching primary_threat will make the standard attack behaviors pick the
	// attacker on the next tick.
	var/mob/old = brain.primary_threat
	brain.primary_threat = target
	if(old != target)
		SEND_SIGNAL(brain.holder, COMSIG_DQAI_TARGET_CHANGED, target, old)
	brain.invalidate_selection()
	return DQ_BEHAVIOR_DONE
