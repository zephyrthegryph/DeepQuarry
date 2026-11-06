/// A pop-up bloodsuck question (Yes/No); carries the target and the privacy answer.
/datum/prompt/choice/bloodsuck
	timeout = 0
	choices = list("Yes", "No")
	buttons = TRUE
	ask_flags = ASK_CONSCIOUS
	var/mob/living/carbon/human/target
	var/subtle

CAPABILITIES(/datum/prompt/choice/bloodsuck)
	ref_one(nameof(target), /mob/living/carbon/human)

/datum/prompt/choice/bloodsuck/prepare(datum/act/A)
	..()
	var/mob/living/carbon/human/captured = target
	rel_clear(src, nameof(target))
	rel_set(src, nameof(target), captured)

/datum/prompt/choice/bloodsuck/begin()
	if(QDELETED(target))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/bloodsuck/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(target) ? "target gone" : null
