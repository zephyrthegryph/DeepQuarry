/datum/shuttle/autodock/ferry
	var/location = FERRY_LOCATION_STATION	//0 = at area_station, 1 = at area_offsite
	var/direction = FERRY_GOING_TO_STATION	//0 = going to station, 1 = going to offsite.

	var/tmp/obj/effect/shuttle_landmark/landmark_station	// the landmark (set the _tag var, New() resolves it)
	var/landmark_station_tag	// the tag it starts as; resolved into landmark_station at init
	var/tmp/obj/effect/shuttle_landmark/landmark_offsite	// the landmark (set the _tag var, New() resolves it)
	var/landmark_offsite_tag	// the tag it starts as; resolved into landmark_offsite at init

	category = /datum/shuttle/autodock/ferry

/datum/shuttle/autodock/ferry/New(_name)
	if(landmark_station_tag)
		rel_set(src, nameof(landmark_station), SSshuttles.get_landmark(landmark_station_tag))
	if(landmark_offsite_tag)
		rel_set(src, nameof(landmark_offsite), SSshuttles.get_landmark(landmark_offsite_tag))

	..(_name, get_location_waypoint(location))

	rel_set(src, nameof(next_location), get_location_waypoint(!location))


//Gets the shuttle landmark associated with the given location (defaults to current location)
/datum/shuttle/autodock/ferry/proc/get_location_waypoint(location_id = null)
	if (isnull(location_id))
		location_id = location

	if (location_id == FERRY_LOCATION_STATION)
		return landmark_station()
	return landmark_offsite()

/datum/shuttle/autodock/ferry/short_jump(destination)
	direction = !location // Heading away from where we currently are
	. = ..()

/datum/shuttle/autodock/ferry/long_jump(destination, obj/effect/shuttle_landmark/interim, travel_time)
	direction = !location // Heading away from where we currently are
	. = ..()

/datum/shuttle/autodock/ferry/perform_shuttle_move()
	..()
	if (current_location() == landmark_station()) location = FERRY_LOCATION_STATION
	if (current_location() == landmark_offsite()) location = FERRY_LOCATION_OFFSITE

// Once we have arrived where we are going, plot a course back!
/datum/shuttle/autodock/ferry/process_arrived()
	..()
	rel_set(src, nameof(next_location), get_location_waypoint(!location))

// Ferry shuttles should generally always be able to dock.  So read the docking codes off of the target.
/datum/shuttle/autodock/ferry/update_docking_target(obj/effect/shuttle_landmark/location)
	..()
	if(active_docking_controller() && active_docking_controller().docking_codes)
		set_docking_codes(active_docking_controller().docking_codes)

/// the landmark resolved from the _tag var
/datum/shuttle/autodock/ferry/proc/landmark_station() as /obj/effect/shuttle_landmark
	return landmark_station

/// the landmark resolved from the _tag var
/datum/shuttle/autodock/ferry/proc/landmark_offsite() as /obj/effect/shuttle_landmark
	return landmark_offsite
