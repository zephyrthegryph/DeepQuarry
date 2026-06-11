// Armadillo / Torta port — restores the docile armadillo AI and Torta's
// voice-triggered "grande" growth gag.
//
// The legacy /datum/ai_holder/simple_mob/armadillo was a passive pet:
// hostile = FALSE, retaliate = TRUE, can_flee = TRUE, flee_when_dying = TRUE,
// dying_threshold = 0.9 (bolts at 90% HP), speak_chance = 1. Nothing bespoke —
// the generic passive/retaliate/flee kit covers it.
//
// Its /torta subtype added an on_hear_say() override that, one second after
// hearing anyone speak, checked the message for "grande" and — if found — grew
// the armadillo very slightly (resize(+0.01)). Torta is the territorial dorm
// armadillo, so spamming "grande" slowly inflates it. Per the hear_say re-open
// pattern (see ports/teppi.dm / ports/poppy.dm), that lives directly on the mob
// now, NOT as a behavior.

/mob/living/simple_mob/animal/passive/armadillo
	// Docile: never aggresses on sight, only fights back when struck.
	ai_attack_on_sight = FALSE

/mob/living/simple_mob/animal/passive/armadillo/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/flee_low_hp,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// ---------------------------------------------------------------------------
// Torta — voice-triggered growth. Hearing "grande" grows it a hair.
// ---------------------------------------------------------------------------

/mob/living/simple_mob/animal/passive/armadillo/torta/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(!speaker || speaker == src)
		return
	var/message = multilingual_to_message(message_pieces)
	if(!message)
		return
	addtimer(CALLBACK(src, PROC_REF(dq_torta_grande), message), 1 SECOND)

/mob/living/simple_mob/animal/passive/armadillo/torta/proc/dq_torta_grande(message)
	if(client || stat == DEAD)
		return
	message = lowertext(message)
	if(findtext(message, "grande"))
		resize(size_multiplier + 0.01)
