/mob/living/carbon/human/proc/telepathy(mob/M as mob in oview())
	set name = "Project mind"
	set desc = "Talk telepathically to someone over a distance."
	set category = "Abilities.General"

	om_prompt(src, src, list("kind" = "text", "message" = "Message:", "title" = "Project mind", "max_length" = MAX_MESSAGE_LEN, "data" = list("target" = M)), PROC_REF(telepathy_entered))

/mob/living/carbon/human/proc/telepathy_entered(mob/user, msg, datum/om/prompt/ask)
	var/mob/M = ask.get("target")
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
