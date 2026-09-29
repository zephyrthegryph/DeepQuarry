//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

// Controls the emergency shuttle. The emergency shuttle world service (was SSemergency_shuttle): the
// launch countdown and escape pod launches run by /datum/om/behaviour/world/emergency_shuttle (1 s).
// On demand: the lane is parked unless a launch countdown or a pod launch batch is in flight.
GLOBAL_DATUM_INIT(emergency_shuttle_service, /datum/world_service/emergency_shuttle, new)

/datum/world_service/emergency_shuttle
	name = "Emergency Shuttle"
	lane = /datum/om/behaviour/world/emergency_shuttle
	on_demand = TRUE
	// The old subsystem was INITSTAGE_LAST with no dependencies (its setup only builds the
	// announcement datums). SSshuttles is the latest-initializing subsystem it relates to (it
	// depends on SSatoms and SSair, and builds the shuttle datums this service drives), so boot
	// right after it; that keeps it after mapload, as INITSTAGE_LAST did.
	needs = list(/datum/controller/subsystem/shuttles)

	/// Relation view: the emergency shuttle (set in shuttle_emergency.dm; the shuttle registry owns it).
	var/datum/shuttle/autodock/ferry/emergency/shuttle
	var/list/escape_pods = list()

	EXPIRY_DECLARE(launch_time) //the time at which the shuttle will be launched
	var/auto_recall = FALSE		//if set, the shuttle will be auto-recalled
	var/evac = FALSE			//1 = emergency evacuation, 0 = crew transfer
	var/wait_for_launch = FALSE	//if the shuttle is waiting to launch
	var/autopilot = TRUE		//set to 0 to disable the shuttle automatically launching

	var/deny_shuttle = FALSE	//allows admins to prevent the shuttle from being called
	var/departed = FALSE		//if the shuttle has left the station at least once

	VAR_PRIVATE/auto_recall_at		//the time at which the shuttle will be auto-recalled
	VAR_PRIVATE/datum/announcement/priority/emergency_shuttle_docked
	VAR_PRIVATE/datum/announcement/priority/emergency_shuttle_called
	VAR_PRIVATE/datum/announcement/priority/emergency_shuttle_recalled
	VAR_PRIVATE/list/current_run

/datum/world_service/emergency_shuttle/initialize()
	initialized = TRUE
	own_set(src, nameof(emergency_shuttle_docked), new /datum/announcement/priority())
	own_set(src, nameof(emergency_shuttle_called), new /datum/announcement/priority())
	own_set(src, nameof(emergency_shuttle_recalled), new /datum/announcement/priority())
	log_world("World service [name] initialized: [length(escape_pods)] escape pods registered.")

/datum/world_service/emergency_shuttle/service_step(resumed)
	if(!resumed)
		if(!wait_for_launch)
			return TRUE

		if(evac && auto_recall && !BEFORE(src, auto_recall_at, CLOCK_WORLD))
			recall()
		if(EXPIRY_EXPIRED(src, launch_time, CLOCK_WORLD))	//time to launch the shuttle
			stop_launch_countdown()

			if(!shuttle.location)	//leaving from the station
				//launch the pods!
				current_run = escape_pods.Copy()

			if(autopilot)
				shuttle.launch(src)

	while(length(current_run))
		if(TICK_CHECK)
			return FALSE
		var/escape_pod = current_run[length(current_run)]
		current_run.len--
		var/datum/shuttle/autodock/ferry/escape_pod/pod = escape_pods[escape_pod]
		if(!istype(pod, /datum/shuttle/autodock/ferry/escape_pod))
			continue
		if(!pod.arming_controller() || pod.arming_controller().armed)
			pod.launch(src)
	return TRUE

//called when the shuttle has arrived.

/datum/world_service/emergency_shuttle/proc/shuttle_arrived()
	if(shuttle.location)	//at station
		return

	if(autopilot)
		set_launch_countdown(SHUTTLE_LEAVETIME)	//get ready to return
		var/estimated_time = round(estimate_launch_time()/60,1)

		if(evac)
			emergency_shuttle_docked.Announce(replacetext(replacetext(using_map.emergency_shuttle_docked_message, "%dock_name%", "[using_map.dock_name]"),  "%ETD%", "[estimated_time] minute\s"), new_sound = ANNOUNCER_MSG_SHUTTLE_EMERG_DOCK)
		else
			GLOB.priority_announcement.Announce(replacetext(replacetext(using_map.shuttle_docked_message, "%dock_name%", "[using_map.dock_name]"),  "%ETD%", "[estimated_time] minute\s"), "Transfer System", ANNOUNCER_MSG_SHUTTLE_ENDROUND_DOCK)

	//arm the escape pods
	if(!evac)
		return

	for(var/key, value in escape_pods)
		var/datum/shuttle/autodock/ferry/escape_pod/pod = value
		if(!istype(pod, /datum/shuttle/autodock/ferry/escape_pod))
			continue
		if(pod.arming_controller())
			pod.arming_controller().arm()

//begins the launch countdown and sets the amount of time left until launch
/datum/world_service/emergency_shuttle/proc/set_launch_countdown(seconds)
	wait_for_launch = TRUE
	EXPIRY_SET(src, launch_time, (seconds * 10), CLOCK_WORLD)
	om_changed(GLOB.emergency_shuttle_service, CHANGE_SHUTTLE_SCHEDULE)
	demand()

/datum/world_service/emergency_shuttle/proc/stop_launch_countdown()
	wait_for_launch = FALSE
	om_changed(GLOB.emergency_shuttle_service, CHANGE_SHUTTLE_SCHEDULE)

//calls the shuttle for an emergency evacuation
/datum/world_service/emergency_shuttle/proc/call_evac()
	if(!can_call())
		return

	//set the launch timer
	autopilot = TRUE
	set_launch_countdown(get_shuttle_prep_time())
	auto_recall_at = rand(world.time + 300, launch_time - 300)

	//reset the shuttle transit time if we need to
	shuttle.move_time = SHUTTLE_TRANSIT_DURATION
	var/estimated_time = round(estimate_arrival_time()/60, 1)

	evac = TRUE
	emergency_shuttle_called.Announce(replacetext(using_map.emergency_shuttle_called_message, "%ETA%", "[estimated_time] minute\s"), new_sound = ANNOUNCER_MSG_SHUTTLE_EMERG_CALLED)
	for(var/type, area in GLOB.areas_by_type)
		if(istype(area, /area/hallway))
			var/area/hallway/our_hallway = area
			our_hallway.readyalert()

//calls the shuttle for a routine crew transfer
/datum/world_service/emergency_shuttle/proc/call_transfer()
	if(!can_call())
		return

	//set the launch timer
	autopilot = TRUE
	set_launch_countdown(get_shuttle_prep_time())
	auto_recall_at = rand(world.time + 300, launch_time - 300)

	//reset the shuttle transit time if we need to
	shuttle.move_time = SHUTTLE_TRANSIT_DURATION
	var/estimated_time = round(estimate_arrival_time()/60, 1)

	GLOB.priority_announcement.Announce(replacetext(replacetext(using_map.shuttle_called_message, "%dock_name%", "[using_map.dock_name]"),  "%ETA%", "[estimated_time] minute\s"), "Transfer System", ANNOUNCER_MSG_SHUTTLE_ENDROUND_CALLED)

//recalls the shuttle
/datum/world_service/emergency_shuttle/proc/recall()
	if(!can_recall())
		return

	stop_launch_countdown()
	shuttle.cancel_launch(src)

	if(evac)
		emergency_shuttle_recalled.Announce(using_map.emergency_shuttle_recall_message, new_sound = ANNOUNCER_MSG_SHUTTLE_EMERG_RECALLED)

		for(var/type, area in GLOB.areas_by_type)
			if(istype(area, /area/hallway))
				var/area/hallway/our_hallway = area
				our_hallway.readyreset()
		evac = FALSE
		return
	GLOB.priority_announcement.Announce(using_map.shuttle_recall_message)

/datum/world_service/emergency_shuttle/proc/can_call()
	if(!GLOB.universe.OnShuttleCall(null))
		return FALSE
	if(deny_shuttle)
		return FALSE
	if(shuttle.moving_status != SHUTTLE_IDLE || !shuttle.location)	//must be idle at centcom
		return FALSE
	if(wait_for_launch)	//already launching
		return FALSE
	return TRUE

//this only returns 0 if it would absolutely make no sense to recall
//e.g. the shuttle is already at the station or wasn't called to begin with
//other reasons for the shuttle not being recallable should be handled elsewhere
/datum/world_service/emergency_shuttle/proc/can_recall()
	if(shuttle.moving_status == SHUTTLE_INTRANSIT)	//if the shuttle is already in transit then it's too late
		return FALSE
	if(!shuttle.location)	//already at the station.
		return FALSE
	if(!wait_for_launch)	//we weren't going anywhere, anyways...
		return FALSE
	return TRUE

/datum/world_service/emergency_shuttle/proc/get_shuttle_prep_time()
	// During mutiny rounds, the shuttle takes twice as long.
	if(SSticker && SSticker.mode)
		return SHUTTLE_PREPTIME * SSticker.mode.shuttle_delay
	return SHUTTLE_PREPTIME


/*
	These procs are not really used by the controller itself, but are for other parts of the
	game whose logic depends on the emergency shuttle.
*/

//returns 1 if the shuttle is docked at the station and waiting to leave
/datum/world_service/emergency_shuttle/proc/waiting_to_leave()
	if(shuttle.location)
		return FALSE	//not at station
	return (wait_for_launch || shuttle.moving_status != SHUTTLE_INTRANSIT)

//so we don't have GLOB.emergency_shuttle_service.shuttle.location everywhere
/datum/world_service/emergency_shuttle/proc/location()
	if(!shuttle)
		return 1 	//if we dont have a shuttle datum, just act like it's at centcom
	return shuttle.location

//returns the time left until the shuttle arrives at it's destination, in seconds
/datum/world_service/emergency_shuttle/proc/estimate_arrival_time()
	var/eta
	if(shuttle.has_arrive_time())
		//we are in transition and can get an accurate ETA
		eta = shuttle.arrive_time
	else
		//otherwise we need to estimate the arrival time using the scheduled launch time
		eta = launch_time + (shuttle.move_time * 10) + (shuttle.warmup_time * 10)
	return (eta - world.time) / 10

//returns the time left until the shuttle launches, in seconds
/datum/world_service/emergency_shuttle/proc/estimate_launch_time()
	return (launch_time - world.time) / 10

/datum/world_service/emergency_shuttle/proc/has_eta()
	return (wait_for_launch || shuttle.moving_status != SHUTTLE_IDLE)

//returns 1 if the shuttle has gone to the station and come back at least once,
//used for game completion checking purposes
/datum/world_service/emergency_shuttle/proc/returned()
	return (departed && shuttle.moving_status == SHUTTLE_IDLE && shuttle.location)	//we've gone to the station at least once, no longer in transit and are idle back at centcom

//returns 1 if the shuttle is not idle at centcom
/datum/world_service/emergency_shuttle/proc/online()
	if(!shuttle)
		return FALSE
	if(!shuttle.location)	//not at centcom
		return TRUE
	if(wait_for_launch || shuttle.moving_status != SHUTTLE_IDLE)
		return TRUE
	return FALSE

//returns 1 if the shuttle is currently in transit (or just leaving) to the station
/datum/world_service/emergency_shuttle/proc/going_to_station()
	return shuttle && (!shuttle.direction && shuttle.moving_status != SHUTTLE_IDLE)

//returns 1 if the shuttle is currently in transit (or just leaving) to centcom
/datum/world_service/emergency_shuttle/proc/going_to_centcom()
	return shuttle && (shuttle.direction && shuttle.moving_status != SHUTTLE_IDLE)

/datum/world_service/emergency_shuttle/proc/get_status_panel_eta()
	if(online())
		if(shuttle.has_arrive_time())
			var/timeleft = GLOB.emergency_shuttle_service.estimate_arrival_time()
			return "ETA-[(timeleft / 60) % 60]:[add_zero(num2text(timeleft % 60), 2)]"

		if(waiting_to_leave())
			if(shuttle.moving_status == SHUTTLE_WARMUP)
				return "Departing..."

			var/timeleft = GLOB.emergency_shuttle_service.estimate_launch_time()
			return "ETD-[(timeleft / 60) % 60]:[add_zero(num2text(timeleft % 60), 2)]"

	return ""

/// Work while a launch countdown runs or escape pods are still being launched.
/datum/world_service/emergency_shuttle/has_work()
	return wait_for_launch || length(current_run)

/// Emergency shuttle launch countdown and escape pods (was SSemergency_shuttle, 1 s). On demand.
/datum/om/behaviour/world/emergency_shuttle
	name = "world: emergency shuttle"
	every = 1 SECOND
	runlevels = RUNLEVEL_GAME

/datum/om/behaviour/world/emergency_shuttle/service()
	return GLOB.emergency_shuttle_service

// The emergency shuttle datum is a round-long SSshuttles registration.
