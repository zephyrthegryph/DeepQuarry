//This is a holder for things like the Skipjack and Nuke shuttle.
// Formerly /datum/shuttle/multi_shuttle
/datum/shuttle/autodock/multi
	var/list/destination_tags
	var/list/destinations_cache
	EXPIRY_DECLARE(last_cache_rebuild_time)
	category = /datum/shuttle/autodock/multi

	var/cloaked = FALSE
	var/can_cloak = FALSE

	var/at_origin = 1
	var/cooldown = 20
	EXPIRY_DECLARE(last_move) //the time at which we last moved

	var/announcer
	var/arrival_message
	var/departure_message

	var/start_location
	var/last_location
	var/return_warning = 0
	var/legit = FALSE

/datum/shuttle/autodock/multi/New()
	..()
	start_location = current_location()
	last_location = current_location()

/datum/shuttle/autodock/multi/proc/set_destination(destination_key, mob/user)
	if(moving_status != SHUTTLE_IDLE)
		return
	var/list/destinations = get_destinations()
	rel_set(src, nameof(next_location), destinations[destination_key])
	if(!next_location())
		WARNING("Shuttle [src] set to destination we can't find: [destination_key]")

/// Name -> landmark, built fresh from the destinations_cache relation list (a deleted landmark leaves it).
/datum/shuttle/autodock/multi/proc/get_destinations()
	if (last_cache_rebuild_time < SSshuttles.last_landmark_registration_time)
		build_destinations_cache()
	var/list/by_name = list()
	for(var/obj/effect/shuttle_landmark/landmark as anything in destinations_cache)
		by_name["[landmark.name]"] = landmark
	return by_name

/datum/shuttle/autodock/multi/proc/build_destinations_cache()
	EXPIRY_STAMP(src, last_cache_rebuild_time, CLOCK_WORLD)
	rel_clear(src, nameof(destinations_cache))
	for(var/destination_tag in destination_tags)
		var/obj/effect/shuttle_landmark/landmark = SSshuttles.get_landmark(destination_tag)
		if (istype(landmark))
			rel_add(src, nameof(destinations_cache), landmark)

/datum/shuttle/autodock/multi/perform_shuttle_move()
	..()
	EXPIRY_STAMP(src, last_move, CLOCK_WORLD)

/datum/shuttle/autodock/multi/proc/announce_departure()
	if(cloaked || isnull(departure_message))
		return
	GLOB.command_announcement.Announce(departure_message, (announcer ? announcer : "[using_map.boss_name]"))

/datum/shuttle/autodock/multi/proc/announce_arrival()
	if(cloaked || isnull(arrival_message))
		return
	GLOB.command_announcement.Announce(arrival_message, (announcer ? announcer : "[using_map.boss_name]"))
