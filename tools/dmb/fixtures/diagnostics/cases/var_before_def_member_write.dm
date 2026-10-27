/datum/e
	var/answered

/datum/e/proc/r(x)
	if(x)
		answered = 1
		return null
	var/datum/answered = new
	return answered
