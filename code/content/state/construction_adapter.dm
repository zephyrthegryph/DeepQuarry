// Preserve the existing atom initialization sandbox for the concrete world.
/datum/state_construction/create(list/arguments)
	return new_unmaterialized(arglist(arguments))
