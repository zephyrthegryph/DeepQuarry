/datum/antagonist/proc/get_starting_locations()
	if(landmark_id)
		starting_locations = list()
		for(var/obj/effect/landmark/L in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
			if(L.name == landmark_id)
				LAZYOR(starting_locations, get_turf(L))

/datum/antagonist/proc/announce_antagonist_spawn()

	if(spawn_announcement)
		if(announced)
			return
		announced = 1
		om_after(src, spawn_announcement_delay, /proc/delayed_command_announcement, "[spawn_announcement]", "[spawn_announcement_title ? spawn_announcement_title : "Priority Alert"]", spawn_announcement_sound)
	return

/datum/antagonist/proc/place_mob(mob/living/mob)
	if(!starting_locations || !length(starting_locations))
		return
	var/turf/T = pick_mobless_turf_if_exists(starting_locations)
	mob.forceMove(T)
