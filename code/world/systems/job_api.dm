/// Ordered job datums, detached from the system's mutable catalog list.
/datum/system/job/proc/occupation_snapshot()
	return occupations.Copy()

/// The respawn chooser retains its associative title-to-datum mapping.
/datum/system/job/proc/job_choices()
	return occupations_by_name.Copy()

/datum/system/job/proc/has_job_title(title)
	return title in occupations_by_name

/datum/system/job/proc/is_initialized()
	return initialized

/datum/system/job/proc/department_count()
	return length(department_datums)

/datum/system/job/proc/department_by_name(name)
	return LAZYACCESS(department_datums, name)

/datum/system/job/proc/department_name_at(index)
	return department_datums[index]

/// Job previews keep their actual cached icon; callers cannot edit the cache list.
/datum/system/job/proc/cached_job_icon(title)
	return job_icon_cache[title]

/datum/system/job/proc/remember_job_icon(title, preview)
	job_icon_cache[title] = preview

/datum/system/job/proc/record_shift_keys(title, list/keys)
	LAZYADDASSOC(shift_keys, title, keys)

/datum/system/job/proc/has_restricted_keys()
	return length(restricted_keys)

/datum/system/job/proc/is_restricted_key(title, key)
	var/list/keys = LAZYACCESS(restricted_keys, title)
	return key in keys
