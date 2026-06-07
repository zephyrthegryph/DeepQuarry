// DQAdd — job-priority pref (the new shape).
//
// Replaces the 15 legacy bitfield prefs (job_civilian_high/med/low,
// job_medsci_*, job_engsec_*, job_talon_*, job_other_*) with a single sparse assoc list:
//
//     list("Captain" = "high", "Bartender" = "low", "Cook" = "med")
//
// Sparse — jobs at "off" are omitted entirely. Adding a department is now a no-op for
// this layer; the buckets are gone. Reads/writes go through the get_job_priority /
// set_job_priority helpers below so the storage shape can change later without touching
// consumers.
//
// The visitor/assistant preview special-case (the ASSISTANT-in-civilian-low sentinel)
// migrates to a separate toggle pref, /datum/preference/toggle/human/prefer_visitor_role.
//
// Migration of existing savefiles happens once in /datum/preferences/update_character()
// when the savefile version bumps from 1 to 2.

/datum/preference/job_priorities
	savefile_key = "job_priorities"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE

/datum/preference/job_priorities/create_default_value()
	return list()

/datum/preference/job_priorities/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/job_priorities/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/job_priorities/is_valid(value)
	return islist(value)

/datum/preference/job_priorities/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/job_priorities/apply_to_living(mob/living/target, value)
	return

/datum/preference/job_priorities/apply_to_silicon(mob/living/silicon/target, value)
	return

/datum/preference/job_priorities/apply_to_animal(mob/living/simple_mob/target, value)
	return

/datum/preference/job_priorities/apply_to_client(client/target, value)
	return


/datum/preference/toggle/human/prefer_visitor_role
	savefile_key = "prefer_visitor_role"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	default_value = FALSE
	can_randomize = FALSE

/datum/preference/toggle/human/prefer_visitor_role/apply_to_human(mob/living/carbon/human/target, value)
	return


// ─── Helper API on /datum/preferences ────────────────────────────────────────────────

/// Returns the priority for the given job title: "off" | "low" | "med" | "high".
/datum/preferences/proc/get_job_priority(job_title)
	if(!job_title)
		return "off"
	var/list/priorities = read_preference(/datum/preference/job_priorities)
	if(!islist(priorities))
		return "off"
	return priorities[job_title] || "off"

/// Sets the priority. "off" removes the entry. Returns TRUE on accepted change.
/datum/preferences/proc/set_job_priority(job_title, priority)
	if(!job_title || !(priority in list("off", "low", "med", "high")))
		return FALSE
	var/list/priorities = read_preference(/datum/preference/job_priorities)
	if(!islist(priorities))
		priorities = list()
	else
		priorities = priorities.Copy()
	if(priority == "off")
		if(!(job_title in priorities))
			return FALSE
		priorities -= job_title
	else
		if(priorities[job_title] == priority)
			return FALSE
		priorities[job_title] = priority
	update_preference_by_type(/datum/preference/job_priorities, priorities)
	return TRUE

/// Returns the list of job titles at the given priority level.
/datum/preferences/proc/get_jobs_at_priority(priority)
	var/list/out = list()
	if(!(priority in list("low", "med", "high")))
		return out
	var/list/priorities = read_preference(/datum/preference/job_priorities)
	if(!islist(priorities))
		return out
	for(var/title in priorities)
		if(priorities[title] == priority)
			out += title
	return out

/// Returns TRUE if any non-off job-priority entry exists.
/datum/preferences/proc/has_any_job_priority()
	var/list/priorities = read_preference(/datum/preference/job_priorities)
	return islist(priorities) && length(priorities) > 0

/// Bridge for legacy call sites that use integer levels (1=high, 2=med, 3=low).
/// Returns TRUE when the job is set at that level. Replaces the bitfield check
/// `GetJobDepartment(job, level) & job.flag` from the old bucket-based shape.
/datum/preferences/proc/job_at_level(job_title, level)
	var/priority = get_job_priority(job_title)
	switch(level)
		if(1)
			return priority == "high"
		if(2)
			return priority == "med"
		if(3)
			return priority == "low"
	return FALSE

/// Returns the highest-priority job datum for this character. Replaces the inline
/// switch-by-department_flag formerly duplicated in get_highest_job() and
/// dress_preview_mob(). When `prefer_visitor_role` is set, returns JOB_ALT_ASSISTANT —
/// this preserves the old "ASSISTANT bit in civilian_low" sentinel semantics under a
/// dedicated, explicit flag.
///
/// Iteration order: SSjob.occupations is pre-sorted by cmp_job_datums (department then
/// sorting_order), so when multiple jobs share "high", the canonical first hit wins.
/datum/preferences/proc/get_highest_job()
	if(read_preference(/datum/preference/toggle/human/prefer_visitor_role))
		return SSjob.get_job(JOB_ALT_ASSISTANT)
	var/list/highs = get_jobs_at_priority("high")
	if(!length(highs))
		return null
	for(var/datum/job/job in SSjob.occupations)
		if(job.title in highs)
			return job
	return null

/// Returns the *effective* gear list for the given job context — the player's "_default"
/// loadout merged with their per-job overrides. Per-job items take precedence for body
/// slots they fill (so a Captain-only Top Hat replaces the Default Bowler), but anything
/// that doesn't conflict stacks. slot_tie and slot-less ("other" bucket) items always
/// stack without eviction.
///
/// Used by SSjob.equip_rank at spawn time and by dress_preview_mob when previewing the
/// character in the lobby.
/datum/preferences/proc/get_loadout_for_job(job_title)
	var/list/gear_list = read_preference(/datum/preference/gear_list)
	if(!islist(gear_list))
		return list()
	var/list/result = list()
	var/list/default_items = islist(gear_list["_default"]) ? gear_list["_default"] : list()
	// Deep-copy metadata so a spawn-time tweak_item that rewrites its own metadata
	// (e.g. randomized reagent fills) can't bleed back into the savefile's default loadout.
	for(var/name in default_items)
		result[name] = check_list_copy(default_items[name])
	if(!job_title || !islist(gear_list[job_title]))
		return result
	var/list/per_job = gear_list[job_title]
	for(var/name in per_job)
		var/datum/gear/G = GLOB.gear_datums[name]
		// Per-job item evicts conflicting default items in the same single-occupancy slot.
		if(G && G.slot && G.slot != slot_tie)
			for(var/existing_name in result.Copy())
				if(existing_name == name)
					continue
				var/datum/gear/existing = GLOB.gear_datums[existing_name]
				if(existing && existing.slot == G.slot)
					result -= existing_name
		// Per-job metadata also gets a deep copy — same reasoning.
		result[name] = check_list_copy(per_job[name])
	return result

/// Like get_loadout_for_job but also returns the set of item names that came from the
/// default loadout (and were NOT overridden by per-job). The UI uses this to mark items
/// as "inherited" so the player knows they came from Default. Returns a list where the
/// key is "items" (the merged list) and "inherited" (set of names from default that
/// survived the merge).
/datum/preferences/proc/get_merged_loadout(job_title)
	var/list/gear_list = read_preference(/datum/preference/gear_list)
	if(!islist(gear_list))
		return list("items" = list(), "inherited" = list())
	var/list/default_items = islist(gear_list["_default"]) ? gear_list["_default"] : list()
	if(!job_title || job_title == "_default" || !islist(gear_list[job_title]))
		// No layering — return default as-is, nothing inherited (we're editing default).
		var/list/copy = list()
		for(var/name in default_items)
			copy[name] = default_items[name]
		return list("items" = copy, "inherited" = list())
	var/list/per_job = gear_list[job_title]
	// Start with default; then per-job items evict + override as in get_loadout_for_job.
	var/list/result = list()
	var/list/inherited = list()
	for(var/name in default_items)
		result[name] = default_items[name]
		inherited[name] = TRUE
	for(var/name in per_job)
		var/datum/gear/G = GLOB.gear_datums[name]
		if(G && G.slot && G.slot != slot_tie)
			for(var/existing_name in result.Copy())
				if(existing_name == name)
					continue
				var/datum/gear/existing = GLOB.gear_datums[existing_name]
				if(existing && existing.slot == G.slot)
					result -= existing_name
					inherited -= existing_name
		result[name] = per_job[name]
		inherited -= name  // per-job overwrites default → no longer counted as inherited
	return list("items" = result, "inherited" = inherited)
