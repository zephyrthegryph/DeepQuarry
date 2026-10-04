/datum/holder/proc/ask_things(mob/user, list/names)
	open_request(src, /datum/prompt/text, PROC_REF(named), answerer = user, title = "Name", question = "Your name?", default = "Bob", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)
	open_request(src, /datum/prompt/text, PROC_REF(said), answerer = user, question = "Say what?", encode = FALSE, multiline = TRUE, timeout = 0)
	open_request(src, /datum/prompt/number, PROC_REF(counted), answerer = user, question = "How many?", min_value = 1, max_value = 10, default = 5, timeout = 30 SECONDS)
	open_request(src, /datum/prompt/choice, PROC_REF(picked), answerer = user, question = "Which?", choices = names, buttons = TRUE, timeout = 0)
	open_request(src, /datum/prompt/color, PROC_REF(tinted), answerer = user, title = "Tint", question = "Pick a tint:", default = "#ff0000", timeout = 0)
	open_request(src, /datum/prompt/yes_no, PROC_REF(sure), answerer = user, question = "Sure?", timeout = 0)
	open_request(src, /datum/prompt/yes_no, TYPE_PROC_REF(/datum/holder, either), answerer = user, question = "Either way?", timeout = 0)
	// a string that names it stays as it is
	var/note = "om_ask(user, /datum/om/prompt/text, PROC_REF(named), message = \"x\")"

/datum/holder/proc/named(datum/act/request/A)
	EVENT_HANDLER
	if(!A.answer)
		return
	// the answer and who gave it
	return "[A.request.answerer] says [A.answer.answer_value]"

/datum/holder/proc/said(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.answer_value)
		return A.answer.answer_value

/datum/holder/proc/counted(datum/act/request/A)
	if(!A.answer)
		return
	return A.answer.answer_value + 1

/datum/holder/proc/picked(datum/act/request/A)
	if(!A.answer)
		return
	switch(A.answer.answer_value)
		if("a")
			open_request(src, /datum/prompt/text, PROC_REF(said), answerer = A.request.answerer, question = "Then?", timeout = 0)
	return TRUE

/datum/holder/proc/sure(datum/act/request/A)
	if(!A.answer || !A.answer.answer_value)
		return
	return A.answer.answer_value

/datum/holder/proc/either(datum/act/request/A)
	if(!A.answer)
		return
	return A.answer.answer_value

/datum/holder/proc/tinted(datum/act/request/A)
	if(!A.answer)
		return
	return A.answer.answer_value
