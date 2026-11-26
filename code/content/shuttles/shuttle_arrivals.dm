// The new arrivals shuttle.
/datum/shuttle/autodock/ferry/arrivals
	category = /datum/shuttle/autodock/ferry/arrivals

	name = "Arrivals"
	location = FERRY_LOCATION_OFFSITE
	warmup_time = 25 // Warmup takes 5 seconds, so 30 total.
	always_process = TRUE
	var/launch_delay = 3
	/// Idle off-station with nobody aboard: it takes no step until a mob enters one of its areas (passenger_entered()).
	var/tmp/awaiting_passengers = FALSE

	// Maps must implement their own subtype for their arrivals shuttle, and define at least:
	// shuttle_area
	// landmark_station (Which should define its dock target)
	// landmark_offsite
	// docking_controller_tag

// For debugging.
/obj/machinery/computer/shuttle_control/arrivals
	name = "shuttle control console"
	req_access = list(ACCESS_CENT_GENERAL)
	shuttle_tag = "Arrivals"

// The shuttle subsystem owns arrivals automation through always_process. The
// mapped console is only a debugging/control surface and has no step work.

// This proc checks if anyone is on the shuttle.
/datum/shuttle/autodock/ferry/arrivals/proc/check_for_passengers()
	for(var/area/A in shuttle_area)
		for(var/mob/living/L in contents_of(A))
			return TRUE
	return FALSE

// This is to stop the shuttle if someone tries to stow away when its leaving.
/datum/shuttle/autodock/ferry/arrivals/post_warmup_checks()
	if(!location) // If we're at station.
		if(check_for_passengers())
			return FALSE
	return TRUE

/datum/shuttle/autodock/ferry/arrivals/shuttle_step()
	if(process_state == IDLE_STATE)

		if(location) // If we're off-station (space).
			if(!check_for_passengers())
				await_passengers()
			else // No point arriving with an empty shuttle.
				set_warmup_time(initial(warmup_time))
				log_world("Arrivals [src]: passengers aboard at the offsite landmark; launching to the station.")
				launch()
				message_passengers("Arriving at [using_map.station_name] in thirty seconds...")
				after(src, 10 SECONDS, PROC_REF(message_passengers), with = list("Arriving at [using_map.station_name] in twenty seconds."))
				after(src, 20 SECONDS, PROC_REF(message_passengers), with = list("Arriving at [using_map.station_name] in ten seconds.  Please buckle up."))

		else // We are at the station.
			if(!check_for_passengers()) // Don't leave with anyone.
				if(launch_delay) // Give some time to get on the docks so people don't get trapped inbetween the dock airlocks.
					launch_delay--
				else
					launch_delay = initial(launch_delay)
					set_warmup_time(0) // Gotta go fast.
					log_world("Arrivals [src]: empty at the station; launching back off-station.")
					launch()

	..() // Do everything else


/// Waiting off-station: its step stops (shuttle_working()) and its areas wake it when a mob comes aboard. It used to search its areas for
/// passengers every 2 s for the whole round (2.3 ms a look on Southern Cross, with no players at all).
/datum/shuttle/autodock/ferry/arrivals/proc/await_passengers()
	awaiting_passengers = TRUE
	log_world("Arrivals [src] has nobody aboard (at [location ? "the offsite landmark" : "the station"]): waiting for a passenger to enter.")
	SSshuttles.watch_for_passengers(src, TRUE)
	refresh_working()

/// A mob (or something carrying one) entered one of its areas: it steps again and looks for passengers.
/datum/shuttle/autodock/ferry/arrivals/proc/passenger_entered()
	if(!awaiting_passengers)
		return
	awaiting_passengers = FALSE
	log_world("Arrivals [src]: a passenger entered; stepping again.")
	SSshuttles.watch_for_passengers(src, FALSE)
	refresh_working()

/datum/shuttle/autodock/ferry/arrivals/shuttle_working()
	return !awaiting_passengers && ..()

/datum/shuttle/autodock/ferry/arrivals/arrived()
	log_world("Arrivals [src] arrived at [current_location()] (location [location ? "offsite" : "station"], docking [shuttle_docking_controller ? "controller present" : "no controller"]).")
	return ..()
