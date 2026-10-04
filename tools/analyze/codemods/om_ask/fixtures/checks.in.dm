/obj/thing/proc/ask_things(mob/user, list/modes, rights)
	om_ask(user, /datum/om/prompt/choice/radial, PROC_REF(mode_chosen), choices = modes, radius = 42, tooltips = TRUE)
	om_ask(user, /datum/om/prompt/choice/radial, PROC_REF(mode_chosen), choices = modes, anchor = user, require_near = TRUE, autopick_single_option = FALSE)
	om_ask(user, /datum/om/prompt/text, PROC_REF(named), message = "Name?", ask_flags = ASK_CARRIED | ASK_CAPABLE)
	om_ask(user, /datum/om/prompt/confirm, PROC_REF(sure), message = "Sure?", requires = PROMPT_ADMIN(rights))
	om_ask(user, /datum/om/prompt/confirm, PROC_REF(sure), message = "Inside?", requires = list(/datum/om/check/inside_target), ask_flags = ASK_ALIVE)
	om_ask(user, /datum/om/prompt/text, PROC_REF(named), message = "Usable?", requires = PROMPT_USABLE_BY("physical"))
	// a check of no shape here
	om_ask(user, /datum/om/prompt/text, PROC_REF(odd), message = "Odd?", requires = list(/datum/om/check/in_hands))

/datum/thing/proc/ask_radial(mob/user, list/modes)
	// not an atom: the ring's default anchor is unknown
	om_ask(user, /datum/om/prompt/choice/radial, PROC_REF(plain_mode), choices = modes)

/obj/thing/proc/mode_chosen(datum/om/prompt/choice/radial/ask)
	return ask.choice

/obj/thing/proc/named(datum/om/prompt/text/ask)
	return ask.text

/obj/thing/proc/odd(datum/om/prompt/text/ask)
	return ask.text

/obj/thing/proc/sure(datum/om/prompt/confirm/ask)
	return ask.yes

/datum/thing/proc/plain_mode(datum/om/prompt/choice/radial/ask)
	return ask.choice
