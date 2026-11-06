/datum/objective/anti_revolution/execute/find_target()
	..()
	if(target && target.current)
		set_explanation_text("[target.current.real_name], the [target.assigned_role] has extracted confidential information above their clearance. Execute [target.p_them()].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/anti_revolution/execute/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("[target.current.real_name], the [!role_type ? target.assigned_role : target.special_role] has extracted confidential information above their clearance. Execute [target.p_them()].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/anti_revolution/execute/check_completion()
	if(target && target.current)
		if(target.current.stat == DEAD || !ishuman(target.current))
			return 1
		return 0
	return 1
