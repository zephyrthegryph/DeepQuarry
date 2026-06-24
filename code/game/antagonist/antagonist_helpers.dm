/datum/antagonist/proc/can_become_antag(datum/mind/player, ignore_role)
	if(player.current)
		if(jobban_isbanned(player.current, bantype))
			return FALSE
		if(!isnewplayer(player.current) && !isobserver(player.current))
			if(!player.current.can_be_antagged) // Stop autotraitoring pAIs!
				return FALSE
	if(!ignore_role)
		if(player.assigned_role in restricted_jobs)
			return FALSE
		if(CONFIG_GET(flag/protect_roles_from_antagonist) && (player.assigned_role in protected_jobs))
			return FALSE
		if(avoid_silicons)
			var/datum/job/J = SSjob.get_job(player.assigned_role)
			if(J)
				if(J.mob_type & JOB_SILICON)
					return FALSE
			else // If SSjob couldn't find a job, they don't have one yet, so the next best thing we can switch on are job preferences
				// was: bitwise-OR three engsec bitfield prefs and AND with (AI_DEPT | CYBORG).
				// New shape: check the player's priority list directly for AI / Cyborg titles.
				var/datum/preferences/_prefs = player.current?.client?.prefs
				if(_prefs && (_prefs.get_job_priority("AI") != "off" || _prefs.get_job_priority("Cyborg") != "off"))
					return FALSE
	return TRUE

/datum/antagonist/proc/antags_are_dead()
	for(var/datum/mind/antag in current_antagonists)
		if(mob_path && !istype(antag.current,mob_path))
			continue
		if(antag.current.stat==2)
			continue
		return 0
	return 1

/datum/antagonist/proc/get_antag_count()
	return current_antagonists ? current_antagonists.len : 0

/datum/antagonist/proc/is_antagonist(datum/mind/player)
	if(player in current_antagonists)
		return 1

/datum/antagonist/proc/is_type(antag_type)
	if(antag_type == id || antag_type == role_text)
		return 1
	return 0

/datum/antagonist/proc/is_votable()
	return (flags & ANTAG_VOTABLE)

/datum/antagonist/proc/can_late_spawn()
	if(!(allow_latejoin))
		return 0
	update_current_antag_max()
	if(get_antag_count() >= cur_max)
		return 0
	return 1

/datum/antagonist/proc/is_latejoin_template()
	return (flags & (ANTAG_OVERRIDE_MOB|ANTAG_OVERRIDE_JOB))
