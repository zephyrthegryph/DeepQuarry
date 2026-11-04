/datum/objective/rev/find_target()
	..()
	if(target && target.current)
		set_explanation_text("Assassinate, capture or convert [target.current.real_name], the [target.assigned_role].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/rev/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("Assassinate, capture or convert [target.current.real_name], the [!role_type ? target.assigned_role : target.special_role].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/rev/check_completion()
	var/rval = 1
	if(target && target.current)
		var/mob/living/carbon/human/H = target.current
		if(!istype(H))
			return 1
		if(H.stat == DEAD || H.restrained())
			return 1
		// Check if they're converted
		if(target in antag_revs().current_antagonists)
			return 1
		var/turf/T = get_turf(H)
		if(T && isNotStationLevel(T.z))			//If they leave the station they count as dead for this
			rval = 2
		return 0
	return rval
