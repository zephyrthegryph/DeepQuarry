/datum/holder/proc/ask_things(mob/user, other, kind)
	// a positional argument after the handler
	om_ask(user, /datum/om/prompt/text, PROC_REF(fine), "extra", message = "Extra?")
	// a subtype carries its own state
	om_ask(user, /datum/om/prompt/confirm/malf, PROC_REF(fine), message = "Malf?")
	// roles and checks
	om_ask(user, /datum/om/prompt/text, PROC_REF(fine), message = "Who?", subject = other)
	// a parameter of no kind here
	om_ask(user, /datum/om/prompt/text, PROC_REF(fine), message = "Odd?", unheard_of = 1)
	// no message
	om_ask(user, /datum/om/prompt/text, PROC_REF(fine))
	// max_length with no name_text to say what it means
	om_ask(user, /datum/om/prompt/text, PROC_REF(fine), message = "Long?", max_length = 40)
	// the handler is a variable
	om_ask(user, /datum/om/prompt/text, kind, message = "Which proc?")
	// a comment inside the call
	om_ask(user, /datum/om/prompt/text, PROC_REF(fine), // the handler
		message = "Commented?")
	// not a statement
	var/ok = list(om_ask(user, /datum/om/prompt/text, PROC_REF(fine), message = "Value?"))
	// the handler reads more of the prompt
	om_ask(user, /datum/om/prompt/text, PROC_REF(greedy), message = "Greedy?")
	// two kinds, one handler
	om_ask(user, /datum/om/prompt/text, PROC_REF(mixed), message = "Text?")
	om_ask(user, /datum/om/prompt/number, PROC_REF(mixed), message = "Number?")
	return ok

/datum/holder/proc/fine(datum/om/prompt/text/ask)
	return ask.text

/datum/holder/proc/greedy(datum/om/prompt/text/ask)
	return ask.asker

/datum/holder/proc/mixed(datum/om/prompt/text/ask)
	return TRUE
