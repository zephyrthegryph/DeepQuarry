// /datum/slime_state — discipline + voice-command + grudges state for xenobio
// slimes. Replaces the equivalent fields/procs on the deleted
// /datum/ai_holder/simple_mob/xenobio_slime.
//
// Lives on the slime mob (var/datum/slime_state/slime_state). The brain reads
// from it; the xenobio system reads from it. Voice commands (on_hear_say) are
// dispatched here.

/mob/living/simple_mob/slime/xenobio
	var/datum/slime_state/slime_state = null

/datum/slime_state
	var/mob/living/simple_mob/slime/xenobio/holder = null
	var/rabid = FALSE
	var/discipline = 0
	var/resentment = 0
	var/obedience = 0
	var/always_stun = FALSE
	var/last_discipline_decay = null
	var/discipline_decay_time = 5 SECONDS
	var/list/grudges = null   // lazylist of /mob/living/carbon/human

/datum/slime_state/New(mob/living/simple_mob/slime/xenobio/owner)
	if(!owner)
		stack_trace("slime_state instantiated with no owner")
		qdel(src)
		return
	holder = owner
	..()

/datum/slime_state/Destroy()
	holder = null
	grudges = null
	return ..()

// ---------------------------------------------------------------------------
// Discipline math (formerly /datum/ai_holder/simple_mob/xenobio_slime).
// ---------------------------------------------------------------------------

/datum/slime_state/proc/is_justified_to_discipline()
	if(!holder || holder.stat >= UNCONSCIOUS || holder.incapacitated(INCAPACITATION_DISABLED))
		return FALSE
	if(rabid)
		return TRUE
	if(holder.ai_brain?.primary_threat)
		var/mob/threat = holder.ai_brain.primary_threat
		if(ishuman(threat))
			var/mob/living/carbon/human/H = threat
			if(istype(H.species, /datum/species/monkey))
				return FALSE  // monkeys are food
		return TRUE
	return FALSE

/datum/slime_state/proc/adjust_discipline(amount, silent)
	if(amount > 0)
		if(rabid)
			return
		if(holder.untamable)
			holder.say("Grrr...")
			holder.add_modifier(/datum/modifier/berserk, 30 SECONDS)
			enrage()
		var/justified = is_justified_to_discipline()
		if(holder.ai_brain)
			holder.ai_brain.lose_target()
		if(justified)
			obedience++
			if(!silent)
				holder.say(pick("Fine...", "Okay...", "Sorry...", "I yield...", "Mercy..."))
		else
			if(prob(resentment * 20))
				enrage()
				holder.say(pick("Evil...", "Kill...", "Tyrant..."))
			else
				if(!silent)
					holder.say(pick("Why...?", "I don't understand...?", "Cruel...", "Stop...", "Nooo..."))
			resentment++
	discipline = between(0, discipline + amount, 10)
	holder.update_mood()

/datum/slime_state/proc/enrage()
	if(holder.harmless)
		return
	rabid = TRUE
	holder.update_mood()
	holder.visible_message(span_danger("\The [holder] enrages!"))

/datum/slime_state/proc/relax()
	if(holder.harmless)
		return
	if(rabid)
		rabid = FALSE
		holder.update_mood()
		holder.visible_message(span_danger("\The [holder] calms down."))

/datum/slime_state/proc/pacify()
	if(holder.ai_brain)
		holder.ai_brain.lose_target()
		holder.ai_brain.set_hostile(FALSE)
	rabid = FALSE
	holder.a_intent = I_HELP

// ---------------------------------------------------------------------------
// Command logic — returns SLIME_COMMAND_* code or FALSE.
// ---------------------------------------------------------------------------

/datum/slime_state/proc/can_command(mob/living/commander)
	if(rabid)
		return FALSE
	if(!holder.ai_brain?.get_hostile())
		return SLIME_COMMAND_OBEY
	if(holder.IIsAlly(commander))
		return SLIME_COMMAND_FACTION
	if(discipline > resentment && obedience >= 5)
		return SLIME_COMMAND_OBEY
	return FALSE

// ---------------------------------------------------------------------------
// Decay tick — called from the slime evolve/reproduce behavior on slow tick.
// ---------------------------------------------------------------------------

/datum/slime_state/proc/discipline_decay()
	if(discipline > 0 && (isnull(last_discipline_decay) || last_discipline_decay + discipline_decay_time < world.time))
		if(!prob(75 + (obedience * 5)))
			adjust_discipline(-1)
			last_discipline_decay = world.time

// ---------------------------------------------------------------------------
// Voice command handler — bound via hear_say re-open.
// ---------------------------------------------------------------------------

/datum/slime_state/proc/on_hear_say(mob/living/speaker, message)
	if(!speaker || !speaker.client)
		return
	if(!(findtext(message, num2text(holder.number)) || findtext(message, holder.name) || findtext(message, "slimes")))
		return

	if(findtext(message, "hello") || findtext(message, "hi") || findtext(message, "greetings"))
		dq_delayed_say(holder, pick("Hello...", "Hi..."), speaker)

	if(findtext(message, "follow") || findtext(message, "come with me"))
		if(!can_command(speaker))
			dq_delayed_say(holder, pick("No...", "I won't follow..."), speaker)
			return
		dq_delayed_say(holder, "Yes... I follow \the [speaker]...", speaker)
		holder.ai_brain?.set_follow(speaker)

	if(findtext(message, "squish"))
		if(!can_command(speaker))
			dq_delayed_say(holder, "No...", speaker)
			return
		spawn(rand(1 SECOND, 2 SECONDS))
			if(QDELETED(holder) || holder.stat >= UNCONSCIOUS)
				return
			holder.squish()

	if(findtext(message, "stop") || findtext(message, "halt") || findtext(message, "cease"))
		if(holder.victim)
			if(!can_command(speaker) || !is_justified_to_discipline())
				dq_delayed_say(holder, "No...", speaker)
				return
			dq_delayed_say(holder, "Fine...", speaker)
			adjust_discipline(1, TRUE)
			holder.stop_consumption()
		if(holder.ai_brain?.primary_threat)
			if(!can_command(speaker) || !is_justified_to_discipline())
				dq_delayed_say(holder, "No...", speaker)
				return
			dq_delayed_say(holder, "Fine...", speaker)
			adjust_discipline(1, TRUE)
			holder.ai_brain.lose_target()
		var/mob/leader = holder.ai_brain?.get_leader()
		if(leader)
			if(can_command(speaker) || leader == speaker)
				dq_delayed_say(holder, "Yes... I'll stop...", speaker)
				holder.ai_brain.lose_follow()
			else
				dq_delayed_say(holder, "No... I'll keep following \the [leader]...", speaker)

/proc/dq_delayed_say(mob/living/speaker, message, mob/listener)
	addtimer(CALLBACK(speaker, TYPE_PROC_REF(/mob, say), message), rand(5, 15))
