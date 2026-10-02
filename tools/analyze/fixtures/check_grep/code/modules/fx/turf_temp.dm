/proc/turf_temp(T, turf, floor, air)
	T.temperature = 5
	turf.temperature
	floor.temperature += 1
	T.temperature // comment
	// T.temperature
	air.temperature
	x = T.temperature_gas
	x = T.temperature // ALLOW(check_grep): ok
