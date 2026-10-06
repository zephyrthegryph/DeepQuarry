#define ALARM_RESET_DELAY 100 // How long will the alarm/trigger remain active once origin/source has been found to be gone?

/datum/alarm_source
	var/source		= null	// The source trigger
	var/source_name = ""	// The name of the source should it be lost (for example a destroyed camera)
	var/duration	= 0		// How long this source will be alarming, 0 for indefinetely.
	var/severity 	= 1		// How severe the alarm from this source is.
	EXPIRY_DECLARE(start_time) // When this source began alarming.
	EXPIRY_DECLARE(end_time)		// Use to set when this trigger should clear, in case the source is lost.

/datum/alarm_source/New(atom/source)
	rel_set(src, nameof(source), source) // a relation: the framework clears it when the source dies
	EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
	source_name = source.get_source_name()

/datum/alarm
	var/tmp/atom/origin	//Used to identify the alarm area.
	var/list/sources		//List of sources triggering the alarm. Used to determine when the alarm should be cleared.
	var/list/cameras				//List of cameras that can be switched to, if the player has that capability.
	var/tmp/area/last_area	//The last acquired area, used should origin be lost (for example a destroyed borg containing an alarming camera).
	var/last_name	//The last acquired name, used should origin be lost
	var/tmp/area/last_camera_area	//The last area in which cameras where fetched, used to see if the camera list should be updated.
	EXPIRY_DECLARE(end_time)//Used to set when this alarm should clear, in case the origin is lost.
	var/hidden = FALSE				//If this alarm can be seen from consoles or other things.

CAPABILITIES(/datum/alarm)
	owns_many(nameof(sources))

/datum/alarm/New(atom/origin, atom/source, duration, severity, hidden)
	rel_set(src, nameof(origin), origin)

	cameras()	// Sets up both cameras and last alarm area.
	set_source_data(source, duration, severity, hidden)


/// Ages its sources (the handler calls it every 2 s while it is up).
/datum/alarm/proc/alarm_tick()
	// Has origin gone missing?
	if(!origin() && !end_time)
		EXPIRY_SET(src, end_time, ALARM_RESET_DELAY, CLOCK_WORLD)
	for(var/datum/alarm_source/AS in sources)
		// Has the alarm passed its best before date?
		if((AS.end_time && ELAPSED_SINCE(src, AS.end_time, CLOCK_WORLD) > 0) || (AS.duration && ELAPSED_SINCE(src, (AS.start_time + AS.duration), CLOCK_WORLD) > 0))
			rel_remove(src, nameof(sources), AS)
			continue
		// Has the source gone missing?	Then reset the normal duration and set end_time
		if(!AS.source && !AS.end_time)	// end_time is used instead of duration to ensure the reset doesn't remain in the future indefinetely.
			AS.duration = 0
			EXPIRY_SET(AS, end_time, ALARM_RESET_DELAY, CLOCK_WORLD)

#undef ALARM_RESET_DELAY

/datum/alarm/proc/set_source_data(atom/source, duration, severity, hidden)
	var/datum/alarm_source/AS = source_entry(source)
	if(!AS)
		AS = new/datum/alarm_source(source)
		rel_add(src, nameof(sources), AS)
		src.hidden = hidden
	// Currently only non-0 durations can be altered (normal alarms VS EMP blasts)
	if(AS.duration)
		duration = duration SECONDS
		AS.duration = duration
	AS.severity = severity
	src.hidden = min(src.hidden, hidden)

/datum/alarm/proc/clear(source)
	var/datum/alarm_source/AS = source_entry(source)
	if(AS)
		rel_remove(src, nameof(sources), AS) // disposes of it

/// The alarm_source entry for `source`, or null. sources is small, so a scan replaces the old entity-keyed lookup list.
/datum/alarm/proc/source_entry(atom/source)
	if(!source)
		return null
	for(var/datum/alarm_source/AS as anything in sources)
		if(AS.source == source)
			return AS
	return null

/datum/alarm/proc/alarm_area()
	if(!origin())
		return last_area()

	last_area = origin().get_alarm_area()
	return last_area()

/datum/alarm/proc/alarm_name()
	if(!origin())
		return last_name

	last_name = origin().get_alarm_name()
	return last_name

/datum/alarm/proc/cameras()
	// If the alarm origin has changed area, for example a borg containing an alarming camera, reset the list of cameras
	if(cameras && (last_camera_area() != alarm_area()))
		cameras = null

	if(!cameras)
		cameras = origin() ? origin().get_alarm_cameras() : last_area()?.get_alarm_cameras()

	last_camera_area = last_area()
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

/// The last acquired area, used should origin be lost (for example a destroyed borg containing an alarming camera).
/datum/alarm/proc/last_area() as /area
	return last_area

/// The last area in which cameras where fetched, used to see if the camera list should be updated.
/datum/alarm/proc/last_camera_area() as /area
	return last_camera_area

/// The alarm's origin (an atom or an area): a relation view, null once the atom is deleted.
/datum/alarm/proc/origin() as /atom
	return origin
