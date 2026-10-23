// The night shift system's API (code/modules/power/nightshift_service.dm declares the system).
//
//   SSnightshift.check_nightshift(forced)                        re-evaluate the night hours and the alert level now
//   SSnightshift.update_nightshift(active, announce, resumed, forced)   start or end the station's night
//
// The system owns one fact, nightshift_active (TRACKED), and touches no APC: an APC on "automatic" reads it through the night_shift_active()
// accessor in its wants_night_lights() contribution to its area's lights_nightshift (doc/rewrite/final_api.html, section 16.11), so a change
// marks those stats and the next drains recompute them.

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

/// The station's night starts or ends. Always completes (the APCs follow through their stats, not a walk); `resumed` and `forced` are kept for
/// the callers that pass them.
/datum/system/nightshift/proc/update_nightshift(active, announce = TRUE, resumed = FALSE, forced = FALSE)
	set_nightshift_active(!!active)
	log_world("NIGHTSHIFT: the station's night is [active ? "on" : "off"][forced ? " (forced)" : ""].")
	if(announce)
		if (active)
			announce("Good evening, crew. To reduce power consumption and stimulate the circadian rhythms of some species, all of the lights aboard the station have been dimmed for the night.")
		else
			announce("Good morning, crew. As it is now day time, all of the lights aboard the station have been restored to their former brightness.")
	return TRUE
