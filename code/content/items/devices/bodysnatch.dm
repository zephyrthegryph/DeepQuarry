/// Re-checked on the answer: the original device is held and victim remains adjacent and alive.
/datum/prompt/choice/bodysnatch
	title = "Confirmation"
	question = "This will swap your mind with the target's mind. This will result in them controlling your body, and you controlling their body. Continue?"
	choices = list("Continue", "Cancel")
	buttons = TRUE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/bodysnatch/recheck_extra()
	var/mob/living/user = answerer
	var/obj/item/bodysnatcher/device = owner
	var/mob/living/victim = subject
	if(!istype(user) || QDELETED(user) || !istype(device) || QDELETED(device) || !istype(victim) || QDELETED(victim))
		return "gone"
	if(user.get_active_hand() != device && user.get_inactive_hand() != device)
		return "not holding it"
	if(user.incapacitated())
		return "not able to"
	if(!user.Adjacent(victim) || victim.stat == DEAD)
		return "no longer a target"
	return null
