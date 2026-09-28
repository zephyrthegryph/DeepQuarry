// Returns the lowest turf available on a given Z-level, defaults to asteroid for Polaris.

/proc/get_base_turf(z)
	if(!using_map.base_turf_by_z["[z]"])
		using_map.base_turf_by_z["[z]"] = /turf/space
	return using_map.base_turf_by_z["[z]"]

//An area can override the z-level base turf, so our solar array areas etc. can be space-based.
/proc/get_base_turf_by_area(turf/T)
	var/area/A = T.loc
	if(A.base_turf)
		return A.base_turf
	return get_base_turf(T.z)

/client/proc/set_base_turf()
	set category = "Debug"
	set name = "Set Base Turf"
	set desc = "Set the base turf for a z-level."

	if(!check_rights_for(src, R_HOLDER))	return

	om_flow_start(/datum/om/flow/set_base_turf, usr, null)

/// "Set Base Turf": the z-level, then the turf path (a cancel resets it to /turf/space).
/datum/om/flow/set_base_turf
	requires = PROMPT_ADMIN(R_HOLDER)
	var/z_level

/datum/om/flow/set_base_turf/start()
	om_ask(actor, /datum/om/prompt/number, PROC_REF(z_entered), message = "Which Z-level do you wish to set the base turf for?")

/datum/om/flow/set_base_turf/proc/z_entered(datum/om/prompt/number/ask)
	z_level = ask.number
	if(!z_level)
		return
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(turf_chosen), title = "Set Base Turf", message = "Please select a turf path (cancel to reset to /turf/space).", choices = typesof(/turf), cancel_answer = /turf/space)

/datum/om/flow/set_base_turf/proc/turf_chosen(datum/om/prompt/choice/ask)
	set_base_turf_answered(actor, z_level, ask.choice || /turf/space)

/proc/set_base_turf_answered(mob/user, choice, new_base_path)
	using_map.base_turf_by_z["[choice]"] = new_base_path
	message_admins("[key_name_admin(user)] has set the base turf for z-level [choice] to [get_base_turf(choice)].")
	log_admin("[key_name(user)] has set the base turf for z-level [choice] to [get_base_turf(choice)].")
