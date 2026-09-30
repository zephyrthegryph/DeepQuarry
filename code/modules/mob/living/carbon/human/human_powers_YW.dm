/mob/living/carbon/human/proc/telepathy(mob/M as mob in oview())
	set name = "Project mind"
	set desc = "Talk telepathically to someone over a distance."
	set category = VERB_CAT_ABILITIES_GENERAL

	om_ask(src, /datum/om/prompt/text/telepathy, PROC_REF(telepathy_entered), title = "Project mind", target = M)

/// A telepathic message; carries who it's sent to.
/datum/om/prompt/text/telepathy
	message = "Message:"
	var/mob/target

/mob/living/carbon/human/proc/telepathy_entered(datum/om/prompt/text/telepathy/ask)
	var/mob/M = ask.target
	var/msg = ask.text
	if(msg)
		var/mob/living/carbon/human/H = M
		log_say("(GreyTP to [key_name(M)]) [msg]", src)
		if(ishuman(M))
			if(H.species.name == src.species.name)
				to_chat(M, span_purple("you hear [src.name]'s voice: <i>[msg]</i>"))
				to_chat(src, span_purple("you said: \"[msg]\" to [M]"))
			else
				to_chat(M, span_purple("you hear a voice echo in your head... <i>[msg]</i>"))
				to_chat(src, span_purple("you said: \"[msg]\" to [M]"))
		else
			to_chat(M, span_purple("you hear a voice echo in your head... <i>[msg]</i>"))
			to_chat(src, span_purple("you said: \"[msg]\" to [M]"))

	return
