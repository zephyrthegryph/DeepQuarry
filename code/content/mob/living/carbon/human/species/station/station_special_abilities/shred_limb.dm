/datum/prompt/choice/shred_limb
	timeout = 0

/datum/prompt/choice/shred_limb/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	var/datum/shred_limb_review/review = owner
	return review.why_not()
