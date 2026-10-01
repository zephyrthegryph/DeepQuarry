// Reduced from the frozen POWER_EV_RETIRED handler. Numeric list keys use
// positional indexing; an empty list does not turn this into an associative map.
// This specimen is compiled offline, never hosted by the correctness gate.
/datum/power_lookup

/proc/read_power_region(list/regions, list/events, at)
	var/datum/power_lookup/network = regions[events[at]]
	if(network)
		regions -= events[at]
	return network

/proc/missing_numeric_region()
	var/list/regions = list()
	return regions[3]
