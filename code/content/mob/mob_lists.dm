//Orders mobs by type then by name
/proc/sort_mobs()
	var/list/moblist = list()
	var/list/sortmob = sort_names(REGISTRY_MEMBERS(REGISTRY_MOBS))
	var/list/after_simplemob_minded = list()
	for(var/mob/observer/eye/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	for(var/mob/observer/blob/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	for(var/mob/living/silicon/ai/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	for(var/mob/living/silicon/pai/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	for(var/mob/living/silicon/robot/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	var/list/delaylist = list()
	for(var/mob/living/carbon/human/M in sortmob)
		if(living_rules_of(M).low_sorting_priority && !M.client)
			delaylist.Add(M)
		else
			if (!M.client && !sparse_get(M, disconnect_time))
				after_simplemob_minded.Add(M)
				continue
			moblist.Add(M)
	moblist.Add(delaylist)
	for(var/mob/living/carbon/brain/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	for(var/mob/living/carbon/alien/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	for(var/mob/observer/dead/M in sortmob)
		moblist += M
	for(var/mob/new_player/M in sortmob)
		moblist += M
	for(var/mob/living/simple_mob/M in sortmob)
		if (!M.client && !sparse_get(M, disconnect_time)) // Addition
			after_simplemob_minded.Add(M)
			continue
		moblist.Add(M)
	moblist.Add(after_simplemob_minded)
	after_simplemob_minded.Cut()
	// ition Start
	for(var/mob/living/dominated_brain/M in sortmob)
		moblist += M
	return moblist

/proc/observe_list_format(input_list)
	if(!islist(input_list))
		return
	var/list/names = list()
	var/list/output_list = list()
	var/list/namecounts = list()
	var/name
	for(var/atom/A in input_list)
		name = A.name
		if(name in names)
			namecounts[name]++
			name = "[name] ([namecounts[name]])"
		else
			names.Add(name)
			namecounts[name] = 1
		if(ismob(A))
			var/mob/M = A
			if(M.real_name && M.real_name != M.name)
				name += " \[[M.real_name]\]"
			if(M.stat == DEAD)
				if(istype(M, /mob/observer/dead/))
					name += " \[ghost\]"
				else
					name += " \[dead\]"
		output_list[name] = A

	return output_list

//Returns a list of all mobs with their name
/proc/getmobs()
	return observe_list_format(sort_mobs())
