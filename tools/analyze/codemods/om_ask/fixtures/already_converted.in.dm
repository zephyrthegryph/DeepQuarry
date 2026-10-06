/datum/holder/proc/ask_things(mob/user)
	open_request(src, /datum/prompt/text, PROC_REF(named), answerer = user, question = "Your name?", timeout = 0)

/datum/holder/proc/named(datum/act/request/A)
	if(!A.answer)
		return
	return A.answer.value
