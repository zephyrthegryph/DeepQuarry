// Actual generic construction; downstream worlds may suppress live registration during it.
GLOBAL_DATUM(state_construction, /datum/state_construction)

/datum/state_construction

/datum/state_construction/proc/create(list/arguments)
	var/path = arguments[1]
	var/list/constructor_arguments = arguments.Copy(2)
	return new path(arglist(constructor_arguments))

/proc/state_new_unmaterialized(path, loc, ...)
	return state_construction().create(args)

/proc/state_construction()
	RETURN_TYPE(/datum/state_construction)
	if(!GLOB.state_construction)
		GLOB.state_construction = new /datum/state_construction
	return GLOB.state_construction
