/datum/prompt/text/slime_docility_name
	title = "Name your new pet"
	max_len = MAX_NAME_LEN
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/slime_docility_name/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null

/datum/prompt/text/slime_docility_name/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer) || QDELETED(subject))
		return "gone"
	if(!isnull(value))
		var/mob/living/M = subject
		if(M.stat == DEAD)
			return "dead"
		if(!M.ai_brain)
			return "no brain"
	return null
