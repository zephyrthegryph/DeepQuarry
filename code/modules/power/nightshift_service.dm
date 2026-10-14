// The night shift system (was SSnightshift). Every 60 s nightshift_step checks the map's night hours and the alert level and sets the
// station's night (nightshift_active); the station's APCs read it through night_shift_active() (nightshift_api.dm).
SYSTEM_DEF(nightshift)
	name = "Night Shift"
	needs = list(/datum/system/atoms)
	periodic_runlevels = RUNLEVELS_DEFAULT
	/// Follows the map's night hours on its own (was can_fire); FALSE when disabled by config or
	/// while an admin holds night shift on or off.
	var/automatic = TRUE
	/// The station's night is on (TRACKED: the APCs' night lighting reads it through the night_shift_active() accessor).
	var/nightshift_active = FALSE
	var/nightshift_first_check = 30 SECONDS

	var/high_security_mode = FALSE

TRACKED(/datum/system/nightshift, nightshift_active)

/datum/system/nightshift/initialize()
	initialized = TRUE
	if(!CONFIG_GET(flag/enable_night_shifts))
		automatic = FALSE
	log_world("World service [name] initialized: [automatic ? "automatic" : "disabled by config"].")

/datum/system/nightshift/reactions()
	. = ..()
	. += every(60 SECONDS, PROC_REF(nightshift_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/nightshift/proc/nightshift_step(dt)
	if(automatic && ELAPSED(SSticker, round_start_time, CLOCK_WORLD) >= nightshift_first_check)
		check_nightshift()
	return STEP_DONE

/datum/system/nightshift/stat_entry(msg)
	return "[..()][automatic ? "Auto" : "Manual"] | [nightshift_active ? "Night" : "Day"]"

/datum/system/nightshift/proc/announce(message)
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
