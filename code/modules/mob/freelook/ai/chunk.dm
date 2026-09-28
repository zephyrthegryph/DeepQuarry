// CAMERA CHUNK
//
// A 16x16 grid of the map with a list of turfs that can be seen, are visible and are dimmed.
// Allows the Eye to stream these chunks and know what it can and cannot see.

/datum/chunk/camera
	/// Cameras in range (REF_WEAK_LIST), revalidated (can_use(), range) on every acquireVisibleTurfs() pass.
	var/list/cameras

/datum/chunk/camera/acquireVisibleTurfs(list/visible)
	for(var/obj/machinery/camera/c as anything in weak_list_live(cameras))

		if(!c.can_use())
			continue

		var/turf/point = locate(src.x + 8, src.y + 8, src.z)
		if(get_dist(point, c) > 24)
			WEAK_LIST_REMOVE(cameras, c)

		for(var/turf/t in c.can_see())
			visible[t] = t

	for(var/mob/living/silicon/ai/AI in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		for(var/turf/t in AI.seen_camera_turfs())
			visible[t] = t

// Create a new camera chunk, since the chunks are made as they are needed.

/datum/chunk/camera/New(loc, x, y, z)
	for(var/obj/machinery/camera/c in range(16, locate(x + 8, y + 8, z)))
		if(c.can_use())
			WEAK_LIST_ADD(cameras, c)
	..()

/mob/living/silicon/proc/provides_camera_vision()
	return 0

/mob/living/silicon/ai/provides_camera_vision()
	return stat != DEAD

/mob/living/silicon/robot/provides_camera_vision()
	return src.camera && src.camera.network.len && (z in using_map.contact_levels)

/mob/living/silicon/ai/proc/seen_camera_turfs()
	return seen_turfs_in_range(src, world.view)

REF_WEAK_LIST(/datum/chunk/camera, "cameras")
