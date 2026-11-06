/datum/objective/anti_revolution/brig
	var/already_completed = 0

/datum/objective/anti_revolution/brig/find_target()
	..()
	if(target && target.current)
		set_explanation_text("Brig [target.current.real_name], the [target.assigned_role] for 20 minutes to set an example.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/anti_revolution/brig/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("Brig [target.current.real_name], the [!role_type ? target.assigned_role : target.special_role] for 20 minutes to set an example.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/anti_revolution/brig/check_completion()
	if(already_completed)
		return 1

	if(target && target.current)
		if(target.current.stat == DEAD)
			return 0
		if(target.is_brigged(10 * 60 * 10))
			already_completed = 1
			return 1
		return 0
	return 0
