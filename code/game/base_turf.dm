// Returns the lowest turf available on a given Z-level, defaults to asteroid for Polaris.

/proc/get_base_turf(z)
	READS_FROM() // the map's per-level setting, not an entity's state
	if(!using_map.base_turf_by_z["[z]"])
		using_map.base_turf_by_z["[z]"] = /turf/space
	return using_map.base_turf_by_z["[z]"]

//An area can override the z-level base turf, so our solar array areas etc. can be space-based.
/proc/get_base_turf_by_area(turf/T)
	READS_FROM(T)
	var/area/A = T.loc
	if(A.base_turf)
		return A.base_turf
	return get_base_turf(T.z)

/client/proc/set_base_turf()
	set category = VERB_CAT_DEBUG
	set name = "Set Base Turf"
	set desc = "Set the base turf for a z-level."

	if(!check_rights_for(src, R_HOLDER))	return

	var/mob/initiator = usr
	initiator?.ask_set_base_turf()

/// The original command actor chooses the level, then the turf path; cancel resets to space.
/datum/prompt/number/base_turf
	rights = R_HOLDER
	min_value = 0
	max_value = INFINITY
	step = 1
	timeout = 0
	question = "Which Z-level do you wish to set the base turf for?"
	recheck_on_open = TRUE

/datum/prompt/choice/base_turf
	title = "Set Base Turf"
	question = "Please select a turf path (cancel to reset to /turf/space)."
	rights = R_HOLDER
	timeout = 0
	var/z_level

/mob/proc/ask_set_base_turf()
	open_request(src, /datum/prompt/number/base_turf, PROC_REF(base_turf_z_entered), answerer = src)

/mob/proc/base_turf_z_entered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	open_request(src, /datum/prompt/choice/base_turf, PROC_REF(base_turf_chosen), answerer = src, z_level = A.answer.value, choices = typesof(/turf))

/mob/proc/base_turf_chosen(datum/act/request/A)
	var/datum/prompt/choice/base_turf/ask = A.request
	if(QDELETED(ask.answerer))
		return
	var/path = ask.value
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value))
			return
		// Old cancel_answer substitutes space but still runs the flow's late rights recheck.
		if(request_recheck(ask))
			return
		path = /turf/space
	set_base_turf_answered(src, ask.z_level, path || /turf/space)

/proc/set_base_turf_answered(mob/user, choice, new_base_path)
	using_map.base_turf_by_z["[choice]"] = new_base_path
	message_admins("[key_name_admin(user)] has set the base turf for z-level [choice] to [get_base_turf(choice)].")
	log_admin("[key_name(user)] has set the base turf for z-level [choice] to [get_base_turf(choice)].")
