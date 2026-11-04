/datum/objective/cult/survive
	explanation_text = "Our knowledge must live on."
	target_amount = 5

/datum/objective/cult/survive/New()
	..()
	explanation_text = "Our knowledge must live on. Make sure at least [target_amount] acolytes escape on the shuttle to spread their work on an another station."

/datum/objective/cult/survive/check_completion()
	var/acolytes_survived = 0
	if(!antag_cult())
		return 0
	for(var/datum/mind/cult_mind in antag_cult().current_antagonists)
		if (cult_mind.current && cult_mind.current.stat!=2)
			var/area/A = get_area(cult_mind.current )
			if ( is_type_in_list(A, GLOB.centcom_areas))
				acolytes_survived++
	if(acolytes_survived >= target_amount)
		return 0
	else
		return 1
