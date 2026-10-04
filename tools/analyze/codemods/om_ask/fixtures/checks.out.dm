/obj/thing/proc/ask_things(mob/user, list/modes, rights)
	open_request(src, /datum/prompt/choice, PROC_REF(mode_chosen), answerer = user, choices = modes, radius = 42, tooltips = TRUE, radial = TRUE, anchor = src, autopick_single_option = TRUE, timeout = 0)
	open_request(src, /datum/prompt/choice, PROC_REF(mode_chosen), answerer = user, choices = modes, anchor = user, require_near = TRUE, autopick_single_option = FALSE, radial = TRUE, timeout = 0)
	open_request(src, /datum/prompt/text, PROC_REF(named), answerer = user, question = "Name?", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	open_request(src, /datum/prompt/yes_no, PROC_REF(sure), answerer = user, question = "Sure?", rights = rights, timeout = 0)
	open_request(src, /datum/prompt/yes_no, PROC_REF(sure), answerer = user, question = "Inside?", ask_flags = ASK_INSIDE | ASK_ALIVE, timeout = 0)
	open_request(src, /datum/prompt/text, PROC_REF(named), answerer = user, question = "Usable?", usable_state = "physical", timeout = 0)
	// a check of no shape here
	om_ask(user, /datum/om/prompt/text, PROC_REF(odd), message = "Odd?", requires = list(/datum/om/check/in_hands))

/datum/thing/proc/ask_radial(mob/user, list/modes)
	// not an atom: the ring's default anchor is unknown
	om_ask(user, /datum/om/prompt/choice/radial, PROC_REF(plain_mode), choices = modes)

/obj/thing/proc/mode_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return A.answer.answer_value

/obj/thing/proc/named(datum/act/request/A)
	if(!A.answer)
		return
	return A.answer.answer_value

/obj/thing/proc/odd(datum/om/prompt/text/ask)
	return ask.text

/obj/thing/proc/sure(datum/act/request/A)
	if(!A.answer || !A.answer.answer_value)
		return
	return A.answer.answer_value

/datum/thing/proc/plain_mode(datum/om/prompt/choice/radial/ask)
	return ask.choice
