/// Legacy state-change entry point; implementation is engine-owned.
/proc/changed(datum/E, channel = CHANGE_EXPLICIT, var_name)
	return state_changed(E, channel, var_name)
