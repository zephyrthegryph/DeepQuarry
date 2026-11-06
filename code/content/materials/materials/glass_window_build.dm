/datum/prompt/choice/glass_window_build
	title = "Window Construction"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/glass_window_build/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer) || QDELETED(subject))
		return "gone"
	return null
