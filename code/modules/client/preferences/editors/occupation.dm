// DQAdd — Occupation / job priority editor.
//
// Backed by the single /datum/preference/job_priorities pref (sparse assoc
// {title: "high"|"med"|"low"}). Adding a department or a job is a /datum/job
// declaration; no pref-side wiring required.
//
// Grouping: jobs display under their primary /datum/department (Command, Security,
// Engineering, …) — matches the late-join screen and ID manifest. The old
// department_flag bucket model is gone.

/datum/preference_editor/occupation
	key = "occupation"
	category = "occupation"
	sort_order = 10
	display_name = "Job Priorities"
	pref_keys = list(
		"job_priorities",
		"prefer_visitor_role",
		"alternate_option",
		"player_alt_titles",
	)

/datum/preference_editor/occupation/build_ui_data(datum/preferences/preferences)
	var/list/jobs_state = list()
	var/list/availability = list()
	var/list/alt_titles_saved = preferences.read_preference(/datum/preference/player_alt_titles) || list()
	var/list/alt_titles_state = list()
	var/high_count = 0
	var/med_count = 0
	var/low_count = 0
	for(var/datum/job/job in SSjob.occupations)
		if(job.title == "AI" || job.title == "Cyborg" || job.title == "NOPE")
			continue
		if(!LAZYLEN(job.departments))
			continue
		var/priority = preferences.get_job_priority(job.title)
		jobs_state["[job.title]"] = priority
		switch(priority)
			if("high") high_count++
			if("med")  med_count++
			if("low")  low_count++
		var/reason = block_reason(preferences, job)
		if(reason)
			availability["[job.title]"] = reason
		if(alt_titles_saved["[job.title]"])
			alt_titles_state["[job.title]"] = alt_titles_saved["[job.title]"]
	return list(
		"job_priority"     = jobs_state,
		"availability"     = availability,
		"alternate_option" = preferences.read_preference(/datum/preference/numeric/human/alternate_option),
		"alt_titles"       = alt_titles_state,
		"counts" = list(
			"high" = high_count,
			"med"  = med_count,
			"low"  = low_count,
		),
	)

/// Null when the player is allowed to set a non-off priority on this job, otherwise
/// a short human-readable reason ("WHITELIST", "AGE 30+", etc.).
/datum/preference_editor/occupation/proc/block_reason(datum/preferences/preferences, datum/job/job)
	if(job.whitelist_only)
		var/client/C = preferences.client
		if(!C || !is_job_whitelisted(C.mob, job.title))
			return "WHITELIST"
	var/min_age = job.get_min_age()
	if(min_age && min_age > 0)
		var/char_age = preferences.read_preference(/datum/preference/numeric/human/age) || 0
		if(char_age < min_age)
			return "AGE [min_age]+"
	return null

/datum/preference_editor/occupation/build_ui_static_data(datum/preferences/preferences)
	var/list/dept_buckets = list()
	var/list/alt_titles_by_job = list()

	for(var/dept_name in SSjob.department_datums)
		var/datum/department/dept = SSjob.department_datums[dept_name]
		if(dept.centcom_only || !dept.visible)
			continue
		var/list/job_entries = list()
		for(var/job_title in dept.primary_jobs)
			var/datum/job/job = dept.primary_jobs[job_title]
			if(!job)
				continue
			if(job.title == "AI" || job.title == "Cyborg" || job.title == "NOPE")
				continue
			job_entries += list(list(
				"title" = job.title,
				"desc" = job.job_description,
				"supervisors" = job.supervisors,
				"selection_color" = job.selection_color || dept.color,
				"sorting_order" = job.sorting_order,
				"whitelist_only" = job.whitelist_only ? TRUE : FALSE,
				"min_age" = job.minimum_character_age,
				"total_positions" = job.total_positions,
				"current_positions" = job.current_positions,
			))
			if(LAZYLEN(job.alt_titles))
				// FLAT string list — `list(title) + job.alt_titles` would carry the assoc-ness
				// (some jobs map name -> typepath), which json_encode emits as an object and
				// breaks React's .map. Iterate keys.
				var/list/title_list = list("[job.title]")
				for(var/alt_key in job.alt_titles)
					title_list += "[alt_key]"
				alt_titles_by_job["[job.title]"] = title_list
		if(!length(job_entries))
			continue
		dept_buckets["[dept.name]"] = list(
			"label" = dept.name,
			"color" = dept.color,
			"sort"  = dept.sorting_order,
			"jobs"  = job_entries,
		)

	return list(
		"departments" = dept_buckets,
		"alt_options" = list(
			list("value" = 0, "label" = "Return to lobby"),
			list("value" = 1, "label" = "Be assigned as Visitor / Assistant"),
			list("value" = 2, "label" = "Be assigned a random job"),
		),
		"alt_titles_by_job" = alt_titles_by_job,
	)

/datum/preference_editor/occupation/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
		if("set_priority")
			var/title = params["job"]
			var/priority = params["priority"]
			return set_priority(preferences, title, priority)
		if("set_alternate_option")
			var/value = text2num(params["value"])
			if(isnull(value) || value < 0 || value > 2)
				return PREF_UPDATE_REJECTED
			preferences.update_preference_by_type(/datum/preference/numeric/human/alternate_option, value)
			return PREF_UPDATE_ACCEPTED
		if("set_alt_title")
			var/title = params["job"]
			var/alt = params["alt"]
			if(!title)
				return PREF_UPDATE_REJECTED
			var/datum/job/job = SSjob.get_job(title)
			if(!job)
				return PREF_UPDATE_REJECTED
			var/list/saved = preferences.read_preference(/datum/preference/player_alt_titles) || list()
			if(!alt || alt == title)
				saved -= title
			else if(LAZYLEN(job.alt_titles) && (alt in job.alt_titles))
				saved[title] = alt
			else
				return PREF_UPDATE_REJECTED
			preferences.update_preference_by_type(/datum/preference/player_alt_titles, saved)
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/occupation/proc/set_priority(datum/preferences/preferences, title, priority)
	if(!title || !(priority in list("off", "low", "med", "high")))
		return PREF_UPDATE_REJECTED
	var/datum/job/job = SSjob.get_job(title)
	if(!job)
		return PREF_UPDATE_REJECTED

	// Allow off unconditionally so players can clear a stale pick if they lost a whitelist
	// or aged the character down.
	if(priority != "off")
		var/reason = block_reason(preferences, job)
		if(reason)
			return PREF_UPDATE_REJECTED

	// New shape: a single set_job_priority call. The old code had to clear three bitfields
	// then OR in the right bit. No buckets, no flag math, no chance of multi-bit-in-high.
	if(preferences.set_job_priority(title, priority))
		return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED
