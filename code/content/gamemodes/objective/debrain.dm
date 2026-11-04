//I want braaaainssss
/datum/objective/debrain/find_target()
	..()
	if(target && target.current)
		set_explanation_text("Steal the brain of [target.current.real_name].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/debrain/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("Steal the brain of [target.current.real_name] the [!role_type ? target.assigned_role : target.special_role].")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/debrain/check_completion()
	if(!target)//If it's a free objective.
		return 1
	if( !owner.current || owner.current.stat==DEAD )//If you're otherwise dead.
		return 0
	if( !target.current || !isbrain(target.current) )
		return 0
	var/atom/A = target.current
	while(A.loc)			//check to see if the brainmob is on our person
		A = A.loc
		if(A == owner.current)
			return 1
	return 0
