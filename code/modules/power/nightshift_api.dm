// The night shift system's API (code/modules/power/nightshift_service.dm declares the system).
//
//   SSnightshift.check_nightshift(forced)                        re-evaluate the night hours and the alert level now
//   SSnightshift.update_nightshift(active, announce, resumed, forced)   dim or restore every station APC's lighting

/datum/system/nightshift/proc/check_nightshift(forced) //This is called from elsewhere, like setting the alert levels, sadly
	var/emergency = GLOB.security_level > SEC_LEVEL_GREEN
	var/announcing = TRUE
	var/night_time = using_map.get_nightshift()
	if(high_security_mode != emergency)
		high_security_mode = emergency
		if(night_time)
			announcing = FALSE
			if(!emergency)
				announce("Restoring night lighting configuration to normal operation.")
			else
				announce("Disabling night lighting: Station is in a state of emergency.")
	if(emergency)
		night_time = FALSE
	if(nightshift_active != night_time)
		return update_nightshift(night_time, announcing, forced = forced)
	return TRUE

/// Returns FALSE when an unforced run yielded; nightshift_step resumes it next tick.
/datum/system/nightshift/proc/update_nightshift(active, announce = TRUE, resumed = FALSE, forced = FALSE)
	if(!resumed)
		currentrun = REGISTRY_COPY(REGISTRY_APCS)
		nightshift_active = active
		if(announce)
			if (active)
				announce("Good evening, crew. To reduce power consumption and stimulate the circadian rhythms of some species, all of the lights aboard the station have been dimmed for the night.")
			else
				announce("Good morning, crew. As it is now day time, all of the lights aboard the station have been restored to their former brightness.")
	for(var/obj/machinery/power/apc/apc as anything in currentrun)
		currentrun -= apc
		if(apc.z in using_map.station_levels)
			apc.set_nightshift(active, TRUE)
		if(!forced && TICK_CHECK)
			return FALSE
	return TRUE
