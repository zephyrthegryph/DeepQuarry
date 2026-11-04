/datum/objective/survive
	explanation_text = "Stay alive until the end."

/datum/objective/survive/check_completion()
	if(!owner.current || owner.current.stat == DEAD || isbrain(owner.current))
		return 0		//Brains no longer win survive objectives. --NEO
	var/mob/living/original = owner.original_character
	if(issilicon(owner.current) && (original && (owner.current != original)))
		return 0
	return 1
