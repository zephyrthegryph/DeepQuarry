/// Picking a victim for a vore ability. Re-checked on the answer: conscious.
/datum/prompt/choice/victim
	timeout = 0
	title = "Victim"
	question = "Please select a target."
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/victim/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	return null

/// Carries the lunge's warm-up and sound.
/datum/prompt/choice/victim/lunge
	var/leap_warmup
	var/leap_sound
