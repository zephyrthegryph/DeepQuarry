/datum/holder/proc/ask_things(mob/user, list/names)
	om_ask(user, /datum/om/prompt/text, PROC_REF(named), title = "Name", message = "Your name?", default = "Bob", max_length = MAX_NAME_LEN)
	om_ask(user, /datum/om/prompt/text, PROC_REF(said), message = "Say what?", encode = FALSE, multiline = TRUE)
	om_ask(user, /datum/om/prompt/number, PROC_REF(counted), message = "How many?", min = 1, max = 10, default = 5, timeout = 30 SECONDS)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(picked), message = "Which?", choices = names, buttons = TRUE)
	om_ask(user, /datum/om/prompt/color, PROC_REF(tinted), title = "Tint", message = "Pick a tint:", default = "#ff0000")
	om_ask(user, /datum/om/prompt/confirm, PROC_REF(sure), message = "Sure?")
	om_ask(user, /datum/om/prompt/confirm, TYPE_PROC_REF(/datum/holder, either), message = "Either way?", answer_on_no = TRUE)
	// a string that names it stays as it is
	var/note = "om_ask(user, /datum/om/prompt/text, PROC_REF(named), message = \"x\")"

/datum/holder/proc/named(datum/om/prompt/text/ask)
	EVENT_HANDLER
	// the answer and who gave it
	return "[ask.answerer] says [ask.text]"

/datum/holder/proc/said(datum/om/prompt/text/ask)
	if(ask.text)
		return ask.text

/datum/holder/proc/counted(datum/om/prompt/number/ask)
	return ask.number + 1

/datum/holder/proc/picked(datum/om/prompt/choice/ask)
	switch(ask.choice)
		if("a")
			om_ask(ask.answerer, /datum/om/prompt/text, PROC_REF(said), message = "Then?")
	return TRUE

/datum/holder/proc/sure(datum/om/prompt/confirm/ask)
	return ask.yes

/datum/holder/proc/either(datum/om/prompt/confirm/ask)
	return ask.yes

/datum/holder/proc/tinted(datum/om/prompt/color/ask)
	return ask.picked_color
