/datum/objective/assassinate/find_target()
	..()
	if(target && target.current)
		set_explanation_text("Assassinate [target.current.real_name], the [target.assigned_role].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/assassinate/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("Assassinate [target.current.real_name], the [!role_type ? target.assigned_role : target.special_role].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/assassinate/check_completion()
	if(target && target.current)
		if(target.current.stat == DEAD || issilicon(target.current) || isbrain(target.current) || target.current.z > 6 || !target.current.ckey) //Borgs/brains/AIs count as dead for traitor objectives. --NeoFite
			return 1
		return 0
	return 1
