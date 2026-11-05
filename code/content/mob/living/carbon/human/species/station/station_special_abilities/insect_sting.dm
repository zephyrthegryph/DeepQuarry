/// Re-checked on the answer: conscious, off cooldown, and next to the target.
/datum/prompt/choice/insect_sting
	timeout = 0
	title = "Target"
	question = "Who will we sting?"
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/insect_sting/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	var/mob/living/L = answerer
	if(!(STATE_PEEK(L, cooldowns, last_special) < world.time) || !L.Adjacent(value))
		return "can't reach"
	return null
