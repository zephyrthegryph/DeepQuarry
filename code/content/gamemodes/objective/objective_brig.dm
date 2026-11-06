// Similar to the anti-rev objective, but for traitors
/datum/objective/brig
	var/already_completed = 0

/datum/objective/brig/find_target()
	..()
	if(target && target.current)
		set_explanation_text("Have [target.current.real_name], the [target.assigned_role] brigged for 10 minutes.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/brig/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("Have [target.current.real_name], the [!role_type ? target.assigned_role : target.special_role] brigged for 10 minutes.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/brig/check_completion()
	if(already_completed)
		return 1

	if(target && target.current)
		if(target.current.stat == DEAD)
			return 0
		// Make the actual required time a bit shorter than the official time
		if(target.is_brigged(10 * 60 * 5))
			already_completed = 1
			return 1
		return 0
	return 0
