#define ALARM_RAISED 1
#define ALARM_CLEARED 0

/datum/alarm_handler
	var/category = ""
	/// Every active alarm (owned), kept sorted. alarm_for() finds one by origin.
	var/list/datum/alarm/alarms
	var/list/listeners				// A list of all objects interested in alarm changes.

CAPABILITIES(/datum/alarm_handler)
	owns_many(nameof(alarms))
	every(2 SECONDS, then(PROC_REF(expire_step)), when = nameof(expiring))

/// TRUE while any alarm is up (a raised alarm sets it); with none left it parks.
/datum/alarm_handler/var/tmp/expiring = FALSE
TRACKED(/datum/alarm_handler, expiring)

/// Expires alarms every 2 s while any is up (a raised alarm starts it); with none left it parks.
/datum/alarm_handler/proc/expire_step(datum/act/tick)
	for(var/datum/alarm/A in alarms)
		A.alarm_tick()
		check_alarm_cleared(A)
	if(!length(alarms))
		set_expiring(FALSE)


/datum/alarm_handler/proc/triggerAlarm(atom/origin, atom/source, duration = 0, severity = 1, hidden = 0)
	var/new_alarm
	//Proper origin and source mandatory
	if(!(origin && source))
		return
	origin = origin.get_alarm_origin()

	new_alarm = 0
	//see if there is already an alarm of this origin
	var/datum/alarm/existing = alarm_for(origin)
	if(existing)
		existing.set_source_data(source, duration, severity, hidden)
	else
		existing = new/datum/alarm(origin, source, duration, severity, hidden)
		new_alarm = 1
		rel_add(src, nameof(alarms), existing)

	set_expiring(TRUE)
	if(new_alarm)
		rel_set(src, nameof(alarms), dd_sortedObjectList(alarms))
		on_alarm_change(existing, ALARM_RAISED)

	return new_alarm

/datum/alarm_handler/proc/clearAlarm(atom/origin, source)
	//Proper origin and source mandatory
	if(!(origin && source))
		return
	origin = origin.get_alarm_origin()

	var/datum/alarm/existing = alarm_for(origin)
	if(existing)
		existing.clear(source)
		return check_alarm_cleared(existing)

/// The active alarm raised for `origin`, or null.
/datum/alarm_handler/proc/alarm_for(atom/origin)
	for(var/datum/alarm/alarm as anything in alarms)
		if(alarm.origin == origin)
			return alarm
	return null

/// An atom being destroyed stops sourcing alarms and leaves the cached camera lists. (An
/// alarm's `origin` is a relation view: it clears by itself.)
/datum/alarm_handler/proc/release_atom(atom/departing)
	if(!departing)
		return
	var/list/datum/alarm/check_alarms = alarms?.Copy()
	for(var/datum/alarm/alarm as anything in check_alarms)
		alarm.clear(departing)
		if(alarm.cameras)
			alarm.cameras -= departing
		check_alarm_cleared(alarm)

/datum/alarm_handler/proc/major_alarms(z)
	return visible_alarms(z)

/datum/alarm_handler/proc/has_major_alarms(z)
	if(!LAZYLEN(alarms))
		return 0

	return LAZYLEN(major_alarms(z))

/datum/alarm_handler/proc/minor_alarms(z)
	return visible_alarms(z)

/datum/alarm_handler/proc/check_alarm_cleared(datum/alarm/alarm)
	if ((alarm.end_time && ELAPSED_SINCE(src, alarm.end_time, CLOCK_WORLD) > 0) || !length(alarm.sources))
		on_alarm_change(alarm, ALARM_CLEARED)
		rel_remove(src, nameof(alarms), alarm) // destroys it
		return 1
	return 0

/datum/alarm_handler/proc/on_alarm_change(datum/alarm/alarm, was_raised)
	for(var/obj/machinery/camera/C in alarm.cameras())
		if(was_raised && !alarm.hidden)
			C.add_network(category)
		else
			C.remove_network(category)
	notify_listeners(alarm, was_raised)

#undef ALARM_RAISED
#undef ALARM_CLEARED

/datum/alarm_handler/proc/get_alarm_severity_for_origin(atom/origin)
	if(!origin)
		return

	origin = origin.get_alarm_origin()
	var/datum/alarm/existing = alarm_for(origin)
	if(!existing)
		return

	return existing.max_severity()

/atom/proc/get_alarm_origin()
	return src

/turf/get_alarm_origin()
	return get_area(src)

/datum/alarm_handler/proc/register_alarm(object, procName)
	LAZYSET(listeners, object, procName)

/datum/alarm_handler/proc/unregister_alarm(object)
	LAZYREMOVE(listeners, object)

/datum/alarm_handler/proc/notify_listeners(alarm, was_raised)
	for(var/listener in listeners)
		call(listener, LAZYACCESS(listeners, listener))(src, alarm, was_raised)

/datum/alarm_handler/proc/visible_alarms(z)
	if(!LAZYLEN(alarms))
		return list()

	var/list/map_levels = using_map.get_map_levels(z)

	var/list/visible_alarms = new()
	for(var/datum/alarm/A in alarms)
		if(A.hidden || (z && !(A.origin()?.z in map_levels)))
			continue
		visible_alarms.Add(A)
	return visible_alarms

