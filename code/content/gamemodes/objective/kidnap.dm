/datum/objective/heist/kidnap/choose_target()
	var/static/list/roles = list(JOB_CHIEF_ENGINEER,JOB_RESEARCH_DIRECTOR,JOB_ROBOTICIST,JOB_CHEMIST,JOB_ENGINEER)
	var/list/possible_targets = list()
	var/list/priority_targets = list()

	for(var/datum/mind/possible_target in ticker_minds())
		if(possible_target != owner && ishuman(possible_target.current) && (possible_target.current.stat != 2) && (!possible_target.special_role))
			possible_targets += possible_target
			for(var/role in roles)
				if(possible_target.assigned_role == role)
					priority_targets += possible_target
					continue

	if(priority_targets.len > 0)
		rel_set(src, nameof(target), pick(priority_targets))
	else if(possible_targets.len > 0)
		rel_set(src, nameof(target), pick(possible_targets))

	if(target && target.current)
		set_explanation_text("We can get a good price for [target.current.real_name], the [target.assigned_role]. Take them alive.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/heist/kidnap/check_completion()
	if(target && target.current)
		if (target.current.stat == 2)
			return 0 // They're dead. Fail.
		//if (!target.current.restrained())
		//	return 0 // They're loose. Close but no cigar.

		var/area/shuttle/skipjack/A = locate() // Shuttle consensing
		for(var/mob/living/carbon/human/M in area_contents_of_type(A, /mob/living/carbon/human))
			if(target.current == M)
				return 1 //They're restrained on the shuttle. Success.
	else
		return 0
