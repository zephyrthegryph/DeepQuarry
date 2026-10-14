// The emergency shuttle system's API (code/modules/shuttles/emergency_shuttle_service.dm declares the system).
//
//   SSemergency_shuttle.call_evac() / call_transfer() / recall()    start or cancel a call
//   SSemergency_shuttle.can_call() / can_recall()                   whether the call may be made
//   SSemergency_shuttle.set_launch_countdown(seconds) / stop_launch_countdown()
//   SSemergency_shuttle.online() / location() / returned() / has_eta() / waiting_to_leave() / going_to_station() / going_to_centcom()
//   SSemergency_shuttle.estimate_arrival_time() / estimate_launch_time() / get_status_panel_eta()
//   SSemergency_shuttle.set_autopilot(enabled)                      let the shuttle launch itself, or hold it for a console
//   SSemergency_shuttle.shuttle_arrived()                           the shuttle docked

//calls the shuttle for an emergency evacuation
/datum/system/emergency_shuttle/proc/call_evac()
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
/datum/system/emergency_shuttle/proc/call_transfer()
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
/datum/system/emergency_shuttle/proc/recall()
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

/datum/system/emergency_shuttle/proc/can_call()
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
/datum/system/emergency_shuttle/proc/can_recall()
	if(!shuttle) // no emergency shuttle on this map (the unit-test map): nothing to recall
		return FALSE
	if(shuttle.moving_status == SHUTTLE_INTRANSIT)	//if the shuttle is already in transit then it's too late
		return FALSE
	if(!shuttle.location)	//already at the station.
		return FALSE
	if(!wait_for_launch)	//we weren't going anywhere, anyways...
		return FALSE
	return TRUE

//begins the launch countdown and sets the amount of time left until launch
/datum/system/emergency_shuttle/proc/set_launch_countdown(seconds)
	wait_for_launch = TRUE
	EXPIRY_SET(src, launch_time, (seconds * 10), CLOCK_WORLD)
	PUBLISH(SSemergency_shuttle, shuttle_schedule_change)
	demand()

/datum/system/emergency_shuttle/proc/stop_launch_countdown()
	wait_for_launch = FALSE
	PUBLISH(SSemergency_shuttle, shuttle_schedule_change)

//returns 1 if the shuttle is not idle at centcom
/datum/system/emergency_shuttle/proc/online()
	if(!shuttle)
		return FALSE
	if(!shuttle.location)	//not at centcom
		return TRUE
	if(wait_for_launch || shuttle.moving_status != SHUTTLE_IDLE)
		return TRUE
	return FALSE

//so we don't have SSemergency_shuttle.shuttle.location everywhere
/datum/system/emergency_shuttle/proc/location()
	if(!shuttle)
		return 1 	//if we dont have a shuttle datum, just act like it's at centcom
	return shuttle.location

//returns 1 if the shuttle has gone to the station and come back at least once,
//used for game completion checking purposes
/datum/system/emergency_shuttle/proc/returned()
	return (departed && shuttle.moving_status == SHUTTLE_IDLE && shuttle.location)	//we've gone to the station at least once, no longer in transit and are idle back at centcom

/datum/system/emergency_shuttle/proc/has_eta()
	return (wait_for_launch || shuttle.moving_status != SHUTTLE_IDLE)

//returns 1 if the shuttle is docked at the station and waiting to leave
/datum/system/emergency_shuttle/proc/waiting_to_leave()
	if(shuttle.location)
		return FALSE	//not at station
	return (wait_for_launch || shuttle.moving_status != SHUTTLE_INTRANSIT)

//returns 1 if the shuttle is currently in transit (or just leaving) to the station
/datum/system/emergency_shuttle/proc/going_to_station()
	return shuttle && (!shuttle.direction && shuttle.moving_status != SHUTTLE_IDLE)

//returns 1 if the shuttle is currently in transit (or just leaving) to centcom
/datum/system/emergency_shuttle/proc/going_to_centcom()
	return shuttle && (shuttle.direction && shuttle.moving_status != SHUTTLE_IDLE)

//returns the time left until the shuttle arrives at it's destination, in seconds
/datum/system/emergency_shuttle/proc/estimate_arrival_time()
	var/eta
	if(shuttle.has_arrive_time())
		//we are in transition and can get an accurate ETA
		eta = shuttle.arrive_time
	else
		//otherwise we need to estimate the arrival time using the scheduled launch time
		eta = launch_time + (shuttle.move_time * 10) + (shuttle.warmup_time * 10)
	return (eta - world.time) / 10

//returns the time left until the shuttle launches, in seconds
/datum/system/emergency_shuttle/proc/estimate_launch_time()
	return (launch_time - world.time) / 10

/datum/system/emergency_shuttle/proc/get_status_panel_eta()
	if(online())
		if(shuttle.has_arrive_time())
			var/timeleft = SSemergency_shuttle.estimate_arrival_time()
			return "ETA-[(timeleft / 60) % 60]:[add_zero(num2text(timeleft % 60), 2)]"

		if(waiting_to_leave())
			if(shuttle.moving_status == SHUTTLE_WARMUP)
				return "Departing..."

			var/timeleft = SSemergency_shuttle.estimate_launch_time()
			return "ETD-[(timeleft / 60) % 60]:[add_zero(num2text(timeleft % 60), 2)]"

	return ""

/datum/system/emergency_shuttle/proc/shuttle_arrived()
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

/datum/system/emergency_shuttle/proc/set_autopilot(enabled)
	autopilot = enabled
