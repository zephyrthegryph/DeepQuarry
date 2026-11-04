/datum/prompt/choice/refinery_filter
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/refinery_filter/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer))
		return "gone"
	if(answerer.stat || answerer.restrained())
		return "cannot use"
