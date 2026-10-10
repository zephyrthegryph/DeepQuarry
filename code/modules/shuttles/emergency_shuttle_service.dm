//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

// Controls the emergency shuttle. The emergency shuttle system (was SSemergency_shuttle): the
// launch countdown and escape pod launches run by shuttle_step (1 s).
// On demand: the work item is parked unless a launch countdown or a pod launch batch is in flight.
SYSTEM_DEF(emergency_shuttle)
	name = "Emergency Shuttle"
	periodic_runlevels = RUNLEVEL_GAME
	// The old subsystem was INITSTAGE_LAST with no dependencies (its setup only builds the
	// announcement datums). SSshuttles is the latest-initializing subsystem it relates to (it
	// depends on SSatoms and SSair, and builds the shuttle datums this service drives), so boot
	// right after it; that keeps it after mapload, as INITSTAGE_LAST did.
	needs = list(/datum/system/shuttles)

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
	/// TRUE while a launch step that ran out of budget waits to resume.
	VAR_PRIVATE/shuttle_resuming = FALSE

CAPABILITIES(/datum/system/emergency_shuttle)
	owns_one(nameof(emergency_shuttle_called), /datum/announcement/priority)
	owns_one(nameof(emergency_shuttle_docked), /datum/announcement/priority)
	owns_one(nameof(emergency_shuttle_recalled), /datum/announcement/priority)

/datum/system/emergency_shuttle/initialize()
	initialized = TRUE
	rel_set(src, nameof(emergency_shuttle_docked), new /datum/announcement/priority())
	rel_set(src, nameof(emergency_shuttle_called), new /datum/announcement/priority())
	rel_set(src, nameof(emergency_shuttle_recalled), new /datum/announcement/priority())
	log_world("World service [name] initialized: [length(escape_pods)] escape pods registered.")

/datum/system/emergency_shuttle/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(shuttle_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// One kernel run: the launch countdown and the escape pod batch; yields over budget, parks when nothing is in flight.
/datum/system/emergency_shuttle/proc/shuttle_step(dt)
	var/done = step_launch(shuttle_resuming)
	shuttle_resuming = !done
	if(!done)
		return STEP_YIELD
	return has_work() ? STEP_DONE : STEP_PARK

/// Wakes the work item after a launch countdown starts.
/datum/system/emergency_shuttle/proc/demand()
	wake_work_item(PROC_REF(shuttle_step))

/// Returns FALSE when the pod batch ran over the tick budget (the step resumes next tick), TRUE otherwise.
/datum/system/emergency_shuttle/proc/step_launch(resumed)
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

/datum/system/emergency_shuttle/proc/get_shuttle_prep_time()
	// During mutiny rounds, the shuttle takes twice as long.
	if(SSticker && ticker_mode())
		return SHUTTLE_PREPTIME * ticker_mode().shuttle_delay
	return SHUTTLE_PREPTIME


/*
	These procs are not really used by the controller itself, but are for other parts of the
	game whose logic depends on the emergency shuttle.
*/

/// Work while a launch countdown runs or escape pods are still being launched.
/datum/system/emergency_shuttle/proc/has_work()
	return wait_for_launch || length(current_run)

// The emergency shuttle datum is a round-long SSshuttles registration.
