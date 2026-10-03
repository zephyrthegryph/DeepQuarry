// The night shift system (was SSnightshift). Every 60 s nightshift_step checks the map's night hours
// and the alert level and dims or restores the station APCs' lighting, yielding across ticks.
SYSTEM_DEF(nightshift)
	name = "Night Shift"
	needs = list(/datum/system/atoms)
	periodic_runlevels = RUNLEVELS_DEFAULT
	/// Follows the map's night hours on its own (was can_fire); FALSE when disabled by config or
	/// while an admin holds night shift on or off.
	var/automatic = TRUE
	var/nightshift_active = FALSE
	var/nightshift_first_check = 30 SECONDS

	var/high_security_mode = FALSE
	var/list/currentrun
	/// TRUE while a lighting change that ran out of budget waits to resume.
	VAR_PRIVATE/shift_resuming = FALSE

/datum/system/nightshift/initialize()
	initialized = TRUE
	if(!CONFIG_GET(flag/enable_night_shifts))
		automatic = FALSE
	log_world("World service [name] initialized: [automatic ? "automatic" : "disabled by config"].")

/datum/system/nightshift/reactions()
	. = ..()
	. += every(60 SECONDS, PROC_REF(nightshift_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/nightshift/proc/nightshift_step(dt)
	var/done = TRUE
	if(shift_resuming)
		done = update_nightshift(resumed = TRUE)
	else if(automatic && ELAPSED(SSticker, round_start_time, CLOCK_WORLD) >= nightshift_first_check)
		done = check_nightshift()
	shift_resuming = !done
	return done ? STEP_DONE : STEP_YIELD

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
