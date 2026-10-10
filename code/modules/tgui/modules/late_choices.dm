/datum/tgui_module/late_choices
	name = "Late Join"

/datum/tgui_module/late_choices/tgui_status(mob/user, datum/tgui_state/state)
	if(!isnewplayer(user))
		return STATUS_CLOSE
	return STATUS_INTERACTIVE

/proc/get_user_job_priority(mob/user, datum/job/job)
	// was: GetJobDepartment(job, level) & job.flag bitwise check per level.
	. = 0
	if(!user?.client?.prefs)
		return
	switch(user.client.prefs.get_job_priority(job.title))
		if("high")
			. = 1
		if("med")
			. = 2
		if("low")
			. = 3

/proc/department_flag_to_name(department)
	switch(department)
		if(DEPARTMENT_COMMAND)
			. = "Command"
		if(DEPARTMENT_SECURITY)
			. = "Security"
		if(DEPARTMENT_ENGINEERING)
			. = "Engineering"
		if(DEPARTMENT_MEDICAL)
			. = "Medical"
		if(DEPARTMENT_RESEARCH)
			. = "Research"
		if(DEPARTMENT_CARGO)
			. = "Supply"
		if(DEPARTMENT_CIVILIAN)
			. = "Service"
		if(DEPARTMENT_PLANET)
			. = "Expedition"
		if(DEPARTMENT_SYNTHETIC)
			. = "Silicon"
		if(DEPARTMENT_TALON)
			. = "Offmap"
		else
			. = "Unknown"

/proc/character_old_enough_for_job(datum/preferences/prefs, datum/job/job)
	if(!job.minimum_character_age && !job.min_age_by_species)
		return TRUE

	var/min_age = job.get_min_age(prefs.read_preference(/datum/preference/choiced/species), prefs.read_preference(/datum/preference/organ_data)?[O_BRAIN])
	if(prefs.read_preference(/datum/preference/numeric/human/age) >= min_age)
		return TRUE
	return FALSE

CAPABILITIES(/datum/tgui_module/late_choices)
	interface("LateChoices")
	op("join", ui_act("join", arg("job", schema_text(4096))), needs(req_bool(PROC_REF(ui_gate), silent = TRUE)), then(PROC_REF(ui_act_join)))

/datum/tgui_module/late_choices/ui_data(datum/act/eval/A)
	var/mob/new_player/user = A.actor
	var/list/data = list()

	var/name = user.client.prefs.read_preference(/datum/preference/toggle/human/name_is_always_random) ? "friend" : user.client.prefs.read_preference(/datum/preference/name/real_name)

	data["name"] = name
	data["duration"] = roundduration2text()

	if(SSemergency_shuttle?.going_to_centcom())
		data["evac"] = "Gone"
	else if(SSemergency_shuttle?.online())
		if(SSemergency_shuttle.evac)
			data["evac"] = "Emergency"
		else
			data["evac"] = "Crew Transfer"
	else
		data["evac"] = "None"

	var/list/jobs = list()

	for(var/datum/job/job in SSjob.occupations)
		if(job && user.IsJobAvailable(job.title))
			// Check for jobs with minimum age requirements
			if(!character_old_enough_for_job(user.client.prefs, job))
				continue

			// Check species job bans... (Only used for shadekin)
			if(job.is_species_banned(user.client.prefs.read_preference(/datum/preference/choiced/species), user.client.prefs.read_preference(/datum/preference/organ_data)?[O_BRAIN]))
				continue

			var/active = 0
			// Only players with the job assigned and AFK for less than 10 minutes count as active
			for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				if(M.mind?.assigned_role == job.title && M.client?.inactivity <= 10 MINUTES)
					active++

			// Figure out departments
			var/list/departments = list()

			for(var/department in job.departments)
				departments += department_flag_to_name(department)

			UNTYPED_LIST_ADD(jobs, list(
				"title" = job.title,
				"priority" = get_user_job_priority(user, job),
				"departments" = departments,
				"current_positions" = job.current_positions,
				"active" = active,
				"offmap" = job.offmap_spawn,
			))

	data["jobs"] = jobs

	return data

/// Only somebody still in the lobby joins (silently: anyone else is just not answered).
/datum/tgui_module/late_choices/proc/ui_gate(datum/act/op/A)
	return isnewplayer(A.actor)

/datum/tgui_module/late_choices/proc/ui_act_join(datum/act/op/A, job_arg)
	var/mob/user = A.actor
	var/mob/new_player/new_user = user
	var/job = job_arg

	if(!CONFIG_GET(flag/enter_allowed))
		to_chat(new_user, span_notice("There is an administrative lock on entering the game!"))
		return
	else if(SSticker && SSticker.mode && SSticker.mode.explosion_in_progress)
		to_chat(new_user, span_danger("The station is currently exploding. Joining would go poorly."))
		return

	var/pref_species = new_user.client.prefs.read_preference(/datum/preference/choiced/species)
	var/datum/species/S = GLOB.all_species[pref_species]
	if(!is_alien_whitelisted(new_user.client, S))
		tgui_alert_async(new_user, "You are currently not whitelisted to play [pref_species].")
		return 0

	if(!(S.spawn_flags & SPECIES_CAN_JOIN))
		tgui_alert_async(new_user,"Your current species, [pref_species], is not available for play on the station.")
		return 0

	new_user.AttemptLateSpawn(job, user)
