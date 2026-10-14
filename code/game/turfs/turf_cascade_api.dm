// The turf cascade system's API (code/game/turfs/turf_cascade_service.dm declares the system).
//
//   SSturf_cascade.start_cascade(start_turf, turf_path, max_per_fire, time_delay, convert_probability)   begin a conversion

/// Starts the turf cascade and wakes the system's work item. If a cascade is already in process, it will not allow another another to start.
/datum/system/turf_cascade/proc/start_cascade(turf/start_turf, turf_path, max_per_fire = DEFAULT_CONVERSION_RATE, time_delay = DEFAULT_CONVERSION_DELAY, convert_probability = DEFAULT_CONVERSION_PROB)
	if(turf_replace_type)
		return
	if(!isturf(start_turf) || !max_per_fire)
		return
	turf_replace_type = turf_path
	remaining_turf.Add(start_turf)
	conversion_rate = max_per_fire
	conversion_probability = convert_probability
	next_group_delay = DEFAULT_CONVERSION_DELAY
	log_world("Turf cascade started at [AREACOORD(start_turf)] converting to [turf_path].")
	wake_work_item(PROC_REF(grow_cascade))

#undef DEFAULT_CONVERSION_RATE
#undef DEFAULT_CONVERSION_PROB
#undef DEFAULT_CONVERSION_DELAY
