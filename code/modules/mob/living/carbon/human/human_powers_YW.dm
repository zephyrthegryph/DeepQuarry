/mob/living/carbon/human/proc/telepathy(mob/M as mob in oview())
	set name = "Project mind"
	set desc = "Talk telepathically to someone over a distance."
	set category = VERB_CAT_ABILITIES_GENERAL

	open_request(src, /datum/prompt/text/telepathy, PROC_REF(telepathy_entered), answerer = src, title = "Project mind", recipient = M, recipient_expected = !isnull(M))

/// A telepathic message; carries who it's sent to.
/datum/prompt/text/telepathy
	question = "Message:"
	timeout = 0
	var/mob/recipient
	var/recipient_expected = FALSE

CAPABILITIES(/datum/prompt/text/telepathy)
	ref_one(nameof(recipient), /mob)

/datum/prompt/text/telepathy/prepare(datum/act/A)
	. = ..()
	var/mob/captured = recipient
	rel_clear(src, nameof(recipient))
	rel_set(src, nameof(recipient), captured)

/datum/prompt/text/telepathy/recheck_extra()
	. = ..()
	if(.)
		return
	return recipient_expected && QDELETED(recipient) ? "gone" : null

/mob/living/carbon/human/proc/telepathy_entered(datum/act/request/A)
	if(!A.answer)
		return
	return apply_telepathy_entered(A)

/mob/living/carbon/human/proc/apply_telepathy_entered(datum/act/request/A)
	var/datum/prompt/text/telepathy/ask = A.request
	var/mob/M = ask.recipient
	var/msg = A.answer.answer_value
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
