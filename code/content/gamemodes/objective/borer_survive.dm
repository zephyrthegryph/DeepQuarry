//Borer objective(s).
/datum/objective/borer_survive
	explanation_text = "Survive in a host until the end of the round."

/datum/objective/borer_survive/check_completion()
	if(owner)
		var/mob/living/simple_mob/animal/borer/B = owner
		var/mob/living/carbon/human/host = B?.borer_host()
		if(istype(B) && B.stat < 2 && host && host.stat < 2) return 1
	return 0
