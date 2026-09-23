#define ALARM_RESET_DELAY 100 // How long will the alarm/trigger remain active once origin/source has been found to be gone?

/datum/alarm_source
	var/source		= null	// The source trigger
	var/source_name = ""	// The name of the source should it be lost (for example a destroyed camera)
	var/duration	= 0		// How long this source will be alarming, 0 for indefinetely.
	var/severity 	= 1		// How severe the alarm from this source is.
	var/start_time	= 0		// When this source began alarming.
	var/end_time	= 0		// Use to set when this trigger should clear, in case the source is lost.
	/// The /datum/alarm that owns this source, so its expiry timer can drop itself from `sources`.
	var/datum/alarm/owner
	/// REACT_AT token for the deadline (end_time, or start_time + duration) that clears this
	/// source; null when neither is set (an indefinite source).
	var/tmp/expire_timer

/datum/alarm_source/New(atom/source)
	src.source = source
	start_time = world.time
	source_name = source.get_source_name()

/datum/alarm_source/Destroy()
	source = null
	owner = null
	return ..()

/// Re-arms `expire_timer` for whichever deadline is currently set (end_time takes priority
/// over start_time + duration, matching the poll this replaced); null if neither is set.
/datum/alarm_source/proc/reschedule_expiry()
	var/deadline = null
	if(end_time)
		deadline = end_time
	else if(duration)
		deadline = start_time + duration
	expire_timer = REACT_REARM(src, expire_timer, deadline)

/datum/alarm_source/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER) || source != expire_timer)
		return
	expire_timer = null
	if(owner)
		owner.sources -= src

/datum/alarm
	var/atom/origin					//Used to identify the alarm area.
	var/list/sources = new()		//List of sources triggering the alarm. Used to determine when the alarm should be cleared.
	var/list/sources_assoc = new()	//Associative list of source triggers. Used to efficiently acquire the alarm source.
	var/list/cameras				//List of cameras that can be switched to, if the player has that capability.
	var/area/last_area				//The last acquired area, used should origin be lost (for example a destroyed borg containing an alarming camera).
	var/area/last_name				//The last acquired name, used should origin be lost
	var/area/last_camera_area		//The last area in which cameras where fetched, used to see if the camera list should be updated.
	var/end_time					//Used to set when this alarm should clear, in case the origin is lost.
	var/hidden = FALSE				//If this alarm can be seen from consoles or other things.

/datum/alarm/New(atom/origin, atom/source, duration, severity, hidden)
	src.origin = origin

	cameras()	// Sets up both cameras and last alarm area.
	set_source_data(source, duration, severity, hidden)

/datum/alarm/Destroy()
	QDEL_LIST(sources)
	sources_assoc = null
	cameras = null
	origin = null
	last_area = null
	last_camera_area = null
	return ..()

/datum/alarm/process()
	// Has origin gone missing?
	if(!origin && !end_time)
		end_time = world.time + ALARM_RESET_DELAY
	for(var/datum/alarm_source/AS in sources)
		// Has the source gone missing?	Then reset the normal duration and set end_time
		if(!AS.source && !AS.end_time)	// end_time is used instead of duration to ensure the reset doesn't remain in the future indefinetely.
			AS.duration = 0
			AS.end_time = world.time + ALARM_RESET_DELAY
			AS.reschedule_expiry()

#undef ALARM_RESET_DELAY

/datum/alarm/proc/set_source_data(atom/source, duration, severity, hidden)
	var/datum/alarm_source/AS = sources_assoc[source]
	if(!AS)
		AS = new/datum/alarm_source(source)
		AS.owner = src
		sources += AS
		sources_assoc[source] = AS
		src.hidden = hidden
	// Currently only non-0 durations can be altered (normal alarms VS EMP blasts)
	if(AS.duration)
		duration = duration SECONDS
		AS.duration = duration
	AS.severity = severity
	AS.reschedule_expiry()
	src.hidden = min(src.hidden, hidden)

/datum/alarm/proc/clear(source)
	var/datum/alarm_source/AS = sources_assoc[source]
	sources -= AS
	sources_assoc -= source
	if(AS)
		AS.source = null
		qdel(AS)

/datum/alarm/proc/alarm_area()
	if(!origin)
		return last_area

	last_area = origin.get_alarm_area()
	return last_area

/datum/alarm/proc/alarm_name()
	if(!origin)
		return last_name

	last_name = origin.get_alarm_name()
	return last_name

/datum/alarm/proc/cameras()
	// If the alarm origin has changed area, for example a borg containing an alarming camera, reset the list of cameras
	if(cameras && (last_camera_area != alarm_area()))
		cameras = null

	if(!cameras)
		cameras = origin ? origin.get_alarm_cameras() : last_area?.get_alarm_cameras()

	last_camera_area = last_area
	return cameras

/datum/alarm/proc/max_severity()
	var/max_severity = 0
	for(var/datum/alarm_source/AS in sources)
		max_severity = max(AS.severity, max_severity)

	return max_severity

/******************
* Assisting procs *
******************/
/atom/proc/get_alarm_area()
	return get_area(src)

/area/get_alarm_area()
	return src

/atom/proc/get_alarm_name()
	var/area/A = get_area(src)
	return A ? A.name : name

/area/get_alarm_name()
	return name

/mob/get_alarm_name()
	return name

/atom/proc/get_source_name()
	return name

/obj/machinery/camera/get_source_name()
	return c_tag

/atom/proc/get_alarm_cameras()
	var/area/A = get_area(src)
	// An origin outside any area (nullspace) has no camera network.
	return A ? A.get_cameras() : list()

/area/get_alarm_cameras()
	return get_cameras()

/mob/living/silicon/robot/get_alarm_cameras()
	var/list/cameras = ..()
	if(camera)
		cameras += camera

	return cameras

/mob/living/silicon/robot/syndicate/get_alarm_cameras()
	return list()
