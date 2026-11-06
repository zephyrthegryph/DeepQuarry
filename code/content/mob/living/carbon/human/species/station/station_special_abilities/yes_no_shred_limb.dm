/datum/prompt/yes_no/shred_limb
	timeout = 0

/datum/prompt/yes_no/shred_limb/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/shred_limb_review/review = owner
	return review.why_not()
