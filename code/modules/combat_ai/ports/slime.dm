// Modern-AI port for xenobio + feral slimes.
//
// Combat AI lives entirely on the brain. Discipline / voice-command / grudge
// state lives on /datum/slime_state (slime_state.dm). The legacy
// /datum/ai_holder/simple_mob/xenobio_slime is gone.
//
// The xenobio code (discipline.dm, xenobio.dm, slime potions, slime scanner)
// reads slime_state directly via the slime mob's proxy procs.

/mob/living/simple_mob/slime
	use_modern_ai = TRUE

/mob/living/simple_mob/slime/xenobio/Initialize(mapload)
	. = ..()
	if(!slime_state)
		slime_state = new /datum/slime_state(src)

/mob/living/simple_mob/slime/xenobio/Destroy()
	QDEL_NULL(slime_state)
	return ..()

/mob/living/simple_mob/slime/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(istype(src, /mob/living/simple_mob/slime/xenobio))
		var/mob/living/simple_mob/slime/xenobio/X = src
		if(X.slime_state)
			X.slime_state.on_hear_say(speaker, multilingual_to_message(message_pieces))

/mob/living/simple_mob/slime/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/slime_evolve_reproduce,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/slime_smart_attack,
		/datum/ai_behavior/ranged_attack,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/slime/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/slime_prefer_food,
		/datum/target_selector/closest,
	)
	return L

// ---------------------------------------------------------------------------
// Slime-aware target selector.
// ---------------------------------------------------------------------------

/datum/target_selector/slime_prefer_food

/datum/target_selector/slime_prefer_food/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/datum/slime_state/state = null
	if(istype(brain.holder, /mob/living/simple_mob/slime/xenobio))
		var/mob/living/simple_mob/slime/xenobio/X = brain.holder
		state = X.slime_state
	// First pass: any monkey is preferred food.
	for(var/mob/living/M as anything in candidates)
		if(!ishuman(M))
			continue
		var/mob/living/carbon/human/H = M
		if(istype(H.species, /datum/species/monkey))
			return H
	// Second pass: filter out prometheans the slime has no grudge against.
	var/list/filtered = list()
	for(var/mob/living/M as anything in candidates)
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species && H.species.name == SPECIES_PROMETHEAN && state && !(H in state.grudges))
				continue
		filtered += M
	if(!length(filtered))
		return null
	return dq_get_selector(/datum/target_selector/closest).select(brain, filtered)

// ---------------------------------------------------------------------------
// Smart attack — intent switching based on target state.
// ---------------------------------------------------------------------------

/datum/ai_behavior/slime_smart_attack
	name = "slime smart attack"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1

/datum/ai_behavior/slime_smart_attack/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/slime)

/datum/ai_behavior/slime_smart_attack/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/slime/SM = brain.holder
	var/mob/threat = brain.primary_threat
	if(!SM || !threat || !SM.Adjacent(threat))
		return null
	if(!SM.checkClickCooldown())
		return null
	// Disciplined non-rabid slimes refuse to attack.
	if(istype(SM, /mob/living/simple_mob/slime/xenobio))
		var/mob/living/simple_mob/slime/xenobio/X = SM
		if(X.slime_state && X.slime_state.discipline && !X.slime_state.rabid)
			SM.a_intent = I_HELP
			return null
	return DQAI_RESULT(45, threat)

/datum/ai_behavior/slime_smart_attack/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/slime/SM = brain.holder
	if(!istype(SM))
		return DQ_BEHAVIOR_FAILED
	if(istype(SM, /mob/living/simple_mob/slime/xenobio) && isliving(target))
		var/mob/living/L = target
		var/mob/living/simple_mob/slime/xenobio/my_slime = SM
		var/always_stun = my_slime.slime_state && my_slime.slime_state.always_stun
		if((!L.lying && prob(30 + (my_slime.power_charge * 7))) || (!L.lying && always_stun))
			my_slime.a_intent = I_DISARM
		else if(my_slime.can_consume(L) && L.lying)
			my_slime.a_intent = I_GRAB
		else
			my_slime.a_intent = I_HURT
	SM.attack_target(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Evolve / reproduce — also ticks discipline decay so the slime calms over time.
// ---------------------------------------------------------------------------

/datum/ai_behavior/slime_evolve_reproduce
	name = "slime evolve / reproduce"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE

/datum/ai_behavior/slime_evolve_reproduce/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/slime/xenobio)

/datum/ai_behavior/slime_evolve_reproduce/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/slime/xenobio/my_slime = brain.holder
	if(!istype(my_slime))
		return null
	// Tick discipline decay every slow evaluate (~2s).
	if(my_slime.slime_state)
		my_slime.slime_state.discipline_decay()
	if(my_slime.amount_grown < 10)
		return null
	return DQAI_RESULT(2, my_slime)

/datum/ai_behavior/slime_evolve_reproduce/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/slime/xenobio/my_slime = brain.holder
	if(my_slime.is_adult)
		my_slime.reproduce()
	else
		my_slime.evolve()
	return DQ_BEHAVIOR_DONE
