// The event world service (fold wave F3; was SSevents): the event containers and the finished
// events. It schedules nothing of its own: each active event and each container runs on the slow
// periodic lane (code/datums/om/periodic.dm), and the running events are REGISTRY_ACTIVE_EVENTS.
// SSatoms.Initialize() calls initialize() once the map is up (the subsystem's atoms dependency).
GLOBAL_DATUM_INIT(event_service, /datum/world_service/events, new)

/datum/world_service/events
	name = "Events"
	boot_after = /datum/controller/subsystem/atoms

	var/list/datum/event/finished_events = list()

	/// Every /datum/event subtype path (type paths, not entities).
	var/list/allEvents
	var/alist/event_containers

	var/datum/event_meta/new_event = new

/datum/world_service/events/initialize()
	if(initialized)
		return
	initialized = TRUE
	allEvents = subtypesof(/datum/event)
	event_containers = list(
			/*EVENT_LEVEL_MUNDANE 	= */ new/datum/event_container/mundane,
			/*EVENT_LEVEL_MODERATE	= */ new/datum/event_container/moderate,
			/*EVENT_LEVEL_MAJOR 	= */ new/datum/event_container/major
		)
	for(var/i = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
		om_task_periodic(event_containers[i], PERIODIC_SLOW)
	if(using_map.use_overmap)
		if(using_map.overmap_z)
			GLOB.overmap_event_handler.create_events(using_map.overmap_z, using_map.overmap_size, using_map.overmap_event_areas)
	log_world("Event service initialized: [length(allEvents)] event types, [length(event_containers)] containers started.")

/datum/world_service/events/stat_line()
	return "E:[REGISTRY_COUNT(REGISTRY_ACTIVE_EVENTS)]"

/// The events that are running now (a copy, safe to walk while events complete).
/datum/world_service/events/proc/active_events()
	return REGISTRY_COPY(REGISTRY_ACTIVE_EVENTS)

/datum/world_service/events/proc/event_complete(datum/event/E)
	registry_leave(REGISTRY_ACTIVE_EVENTS, E)
	om_task_periodic_stop(E)

	if(!E.event_meta() || !E.severity)	// datum/event is used here and there for random reasons, maintaining "backwards compatibility"
		log_game("Event of '[E.type]' with missing meta-data has completed.")
		return

	own_add(src, "finished_events", E)

	// Add the event back to the list of available events
	var/datum/event_container/EC = event_containers[E.severity]
	var/datum/event_meta/EM = E.event_meta()
	if(EM.add_to_queue)
		EC.available_events += EM

	log_game("Event '[EM.name]' has completed at [stationtime2text()].")

/datum/world_service/events/proc/delay_events(severity, delay)
	var/datum/event_container/EC = event_containers[severity]
	EC.next_event_time += delay

/datum/world_service/events/proc/RoundEnd()
	if(!report_at_round_end)
		return

	to_chat(world, "<br><br><br>" + span_large(span_bold("Random Events This Round:")))
	for(var/datum/event/E in active_events() | finished_events)
		var/datum/event_meta/EM = E.event_meta()
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

