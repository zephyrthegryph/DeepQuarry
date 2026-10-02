// The night shift world service (fold wave F4; was SSnightshift). Every 60 s
// /datum/om/behaviour/world/nightshift (code/datums/om/world_lanes.dm) checks the map's night hours
// and the alert level and dims or restores the station APCs' lighting, yielding across ticks.
GLOBAL_DATUM_INIT(nightshift_service, /datum/world_service/nightshift, new)

/datum/world_service/nightshift
	name = "Night Shift"
	needs = list(/datum/system/atoms)
	lane = /datum/om/behaviour/world/nightshift
	/// Follows the map's night hours on its own (was can_fire); FALSE when disabled by config or
	/// while an admin holds night shift on or off.
	var/automatic = TRUE
	var/nightshift_active = FALSE
	var/nightshift_first_check = 30 SECONDS

	var/high_security_mode = FALSE
	var/list/currentrun

/datum/world_service/nightshift/initialize()
	initialized = TRUE
	if(!CONFIG_GET(flag/enable_night_shifts))
		automatic = FALSE
	log_world("World service [name] initialized: [automatic ? "automatic" : "disabled by config"].")

/datum/world_service/nightshift/service_step(resumed)
	if(resumed)
		return update_nightshift(resumed = TRUE)
	if(!automatic)
		return TRUE
	if(ELAPSED(SSticker, round_start_time, CLOCK_WORLD) < nightshift_first_check)
		return TRUE
	return check_nightshift()

/datum/world_service/nightshift/stat_line()
	return "[automatic ? "Auto" : "Manual"] | [nightshift_active ? "Night" : "Day"]"

/datum/world_service/nightshift/proc/announce(message)
	var/announce_z
	if(length(using_map.station_levels))
		announce_z = pick(using_map.station_levels)
	// TTS
	var/pickedsound
	if(!high_security_mode)
		if(nightshift_active)
			pickedsound = ANNOUNCER_MSG_NIGHTSHIFT_START
		else
			pickedsound = ANNOUNCER_MSG_NIGHTSHIFT_END
	GLOB.priority_announcement.Announce(message, new_title = "Automated Lighting System Announcement", new_sound = pickedsound, zlevel = announce_z)

/datum/world_service/nightshift/proc/check_nightshift(forced) //This is called from elsewhere, like setting the alert levels, sadly
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

/// Returns FALSE when a lane-driven (unforced) run yielded; the lane resumes it next tick.
/datum/world_service/nightshift/proc/update_nightshift(active, announce = TRUE, resumed = FALSE, forced = FALSE)
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
