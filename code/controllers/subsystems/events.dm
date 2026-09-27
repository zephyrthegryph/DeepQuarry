/// Event bookkeeping: the containers and the active and finished events. It schedules nothing:
/// each active event and each container runs on the slow periodic lane (code/datums/om/periodic.dm).
SUBSYSTEM_DEF(events)
	name = "Events"
	flags = SS_NO_FIRE
	dependencies = list(
		/datum/controller/subsystem/atoms
	)

	var/list/datum/event/active_events = list()
	var/list/datum/event/finished_events = list()

	var/list/datum/event/allEvents
	var/alist/event_containers

	var/datum/event_meta/new_event = new

/datum/controller/subsystem/events/Initialize()
	allEvents = subtypesof(/datum/event)
	event_containers = list(
			/*EVENT_LEVEL_MUNDANE 	= */ new/datum/event_container/mundane,
			/*EVENT_LEVEL_MODERATE	= */ new/datum/event_container/moderate,
			/*EVENT_LEVEL_MAJOR 	= */ new/datum/event_container/major
		)
	for(var/i = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
		PERIODIC_START(event_containers[i], PERIODIC_SLOW)
	if(using_map.use_overmap)
		if(using_map.overmap_z)
			GLOB.overmap_event_handler.create_events(using_map.overmap_z, using_map.overmap_size, using_map.overmap_event_areas)
	return SS_INIT_SUCCESS

/datum/controller/subsystem/events/stat_entry(msg)
	msg = "E:[length(active_events)]"
	return ..()

/datum/controller/subsystem/events/Recover()
	if(SSevents.active_events)
		active_events |= SSevents.active_events
	if(SSevents.finished_events)
		finished_events |= SSevents.finished_events

/datum/controller/subsystem/events/proc/event_complete(datum/event/E)
	active_events -= E
	PERIODIC_STOP(E)

	if(!E.event_meta || !E.severity)	// datum/event is used here and there for random reasons, maintaining "backwards compatibility"
		log_game("Event of '[E.type]' with missing meta-data has completed.")
		return

	finished_events += E

	// Add the event back to the list of available events
	var/datum/event_container/EC = event_containers[E.severity]
	var/datum/event_meta/EM = E.event_meta
	if(EM.add_to_queue)
		EC.available_events += EM

	log_game("Event '[EM.name]' has completed at [stationtime2text()].")

/datum/controller/subsystem/events/proc/delay_events(severity, delay)
	var/datum/event_container/EC = event_containers[severity]
	EC.next_event_time += delay

/datum/controller/subsystem/events/proc/RoundEnd()
	if(!report_at_round_end)
		return

	to_chat(world, "<br><br><br>" + span_large(span_bold("Random Events This Round:")))
	for(var/datum/event/E in active_events|finished_events)
		var/datum/event_meta/EM = E.event_meta
		if(EM.name == "Nothing")
			continue
		var/message = "'[EM.name]' began at [worldtime2stationtime(E.startedAt)] "
		if(E.isRunning)
			message += "and is still running."
		else
			if(E.endedAt - E.startedAt > 5 MINUTES) // Only mention end time if the entire duration was more than 5 minutes
				message += "and ended at [worldtime2stationtime(E.endedAt)]."
			else
				message += "and ran to completion."
		to_chat(world, message)
