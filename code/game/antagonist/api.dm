

/datum/system/antag/proc/get_antag_data(antag_type)
	return all_antag_types[antag_type]

/datum/system/antag/proc/get_antags(atype)
	var/datum/antagonist/antag = all_antag_types[atype]
	if(antag && islist(antag.current_antagonists))
		return antag.current_antagonists
	return list()

/datum/system/antag/proc/player_is_antag(datum/mind/player, only_offstation_roles = FALSE)
	for(var/antag_type, value in all_antag_types)
		var/datum/antagonist/antag = value
		if(only_offstation_roles && !(antag.flags & ANTAG_OVERRIDE_JOB))
			continue
		if(player in antag.current_antagonists)
			return TRUE
		if(player in antag.pending_antagonists)
			return TRUE
	return FALSE

/datum/system/antag/proc/clear_antag_roles(datum/mind/player, implanted)
	for(var/antag_type, value in all_antag_types)
		var/datum/antagonist/antag = value
		if(!implanted || !(antag.flags & ANTAG_IMPLANT_IMMUNE))
			antag.remove_antagonist(player, 1, implanted)

/datum/system/antag/proc/update_antag_icons(datum/mind/player)
	for(var/antag_type, value in all_antag_types)
		var/datum/antagonist/antag = value
		if(player)
			antag.update_icons_removed(player)
			if(antag.is_antagonist(player))
				antag.update_icons_added(player)
		else
			antag.update_all_icons()
