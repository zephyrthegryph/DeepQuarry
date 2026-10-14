/datum/state/proc/set_by_name(E, name, v)
	E.vars[name] = v
	vars["x"] = 1
