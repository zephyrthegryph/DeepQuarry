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

	om_prompt_sequence(src, usr, list(
		list("key" = "z", "kind" = "number", "message" = "Which Z-level do you wish to set the base turf for?"),
		list("key" = "turf", "kind" = "list", "message" = "Please select a turf path (cancel to reset to /turf/space).", "title" = "Set Base Turf", "choices" = typesof(/turf)),
	), /client/proc/set_base_turf_answered, list("requires" = PROMPT_ADMIN(R_HOLDER)))

/client/proc/set_base_turf_answered(mob/user, datum/om/prompt/ask)
	var/choice = ask.get("z")
	if(!choice)
		return
	var/new_base_path = ask.get("turf") || /turf/space
	using_map.base_turf_by_z["[choice]"] = new_base_path
	message_admins("[key_name_admin(user)] has set the base turf for z-level [choice] to [get_base_turf(choice)].")
	log_admin("[key_name(user)] has set the base turf for z-level [choice] to [get_base_turf(choice)].")
