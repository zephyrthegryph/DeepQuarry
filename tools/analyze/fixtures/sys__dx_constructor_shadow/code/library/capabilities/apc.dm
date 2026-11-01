
/proc/power_channels(list/channels)
	return list(new /datum/capability/power_channels)
/proc/wires_of(atom/A)
	return cap_of(A, /datum/capability/wires)
/proc/cap_of(atom/A, key)
	return null
